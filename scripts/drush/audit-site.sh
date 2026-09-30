#!/usr/bin/env bash
# audit-site.sh — Full Drupal site audit via drush
# Collects: Drupal version, PHP version, DB info, modules, content counts,
# taxonomy terms, media, users, files, revisions, multilingual status.
# Outputs JSON to stdout.
set -euo pipefail

##############################################################################
# Helpers
##############################################################################

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Perform a full site audit of a Drupal installation via drush.

Options:
  --output-dir DIR   Write audit.json to DIR instead of stdout
  --help             Show this help message
EOF
  exit 0
}

require_drush() {
  if ! command -v drush &>/dev/null; then
    echo "Error: drush is not installed or not in PATH." >&2
    exit 1
  fi
}

# Pretty-print JSON if jq is available, otherwise pass through
json_fmt() {
  if command -v jq &>/dev/null; then
    jq .
  else
    cat
  fi
}

# Run a drush sql:query, trim trailing whitespace
sql() {
  drush sql:query "$1" 2>/dev/null | sed 's/[[:space:]]*$//' || true
}

# Detect Drupal major version (7, 8, 9, 10, 11…)
detect_major() {
  local ver
  ver=$(drush status --field=drupal-version 2>/dev/null || true)
  echo "${ver%%.*}"
}

##############################################################################
# Parse arguments
##############################################################################

OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --help) usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

require_drush

##############################################################################
# Collect data
##############################################################################

MAJOR=$(detect_major)

# --- Core info ---------------------------------------------------------------
DRUPAL_VERSION=$(drush status --field=drupal-version 2>/dev/null || echo "unknown")
PHP_VERSION=$(drush status --field=php-version 2>/dev/null || echo "unknown")
DB_DRIVER=$(drush status --field=db-driver 2>/dev/null || echo "unknown")
DB_NAME=$(drush status --field=db-name 2>/dev/null || echo "unknown")
SITE_URI=$(drush status --field=uri 2>/dev/null || echo "unknown")
FILES_PATH=$(drush status --field=files 2>/dev/null || echo "unknown")

# Database size (MySQL/MariaDB)
DB_SIZE="null"
if [[ "$DB_DRIVER" =~ mysql|mariadb ]]; then
  DB_SIZE=$(sql "SELECT ROUND(SUM(data_length + index_length) / 1024 / 1024, 2)
                 FROM information_schema.tables
                 WHERE table_schema = DATABASE();" | tail -1)
  DB_SIZE="\"${DB_SIZE:-0} MB\""
fi

# --- Enabled modules with versions -------------------------------------------
MODULES_JSON="[]"
if [[ "$MAJOR" == "7" ]]; then
  # D7: drush pm-list outputs a table; parse it
  MODULES_JSON=$(drush pm-list --status=enabled --format=json 2>/dev/null || echo "[]")
else
  # D9+: drush pm:list --status=enabled --format=json
  MODULES_JSON=$(drush pm:list --status=enabled --format=json 2>/dev/null || echo "[]")
fi

# --- Content counts per node type --------------------------------------------
CONTENT_COUNTS="[]"
if [[ "$MAJOR" == "7" ]]; then
  CONTENT_COUNTS=$(sql "SELECT CONCAT('{\"type\":\"', type, '\",\"count\":', COUNT(*), '}')
                        FROM node GROUP BY type;" \
    | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
else
  CONTENT_COUNTS=$(sql "SELECT CONCAT('{\"type\":\"', type, '\",\"count\":', COUNT(*), '}')
                        FROM node_field_data GROUP BY type;" \
    | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
fi
[[ -z "$CONTENT_COUNTS" || "$CONTENT_COUNTS" == "[]" ]] && CONTENT_COUNTS="[]"

# --- Taxonomy term counts per vocabulary -------------------------------------
TAXONOMY_COUNTS="[]"
if [[ "$MAJOR" == "7" ]]; then
  TAXONOMY_COUNTS=$(sql "SELECT CONCAT('{\"vocabulary\":\"', v.machine_name, '\",\"count\":', COUNT(t.tid), '}')
                         FROM taxonomy_term_data t
                         JOIN taxonomy_vocabulary v ON t.vid = v.vid
                         GROUP BY v.machine_name;" \
    | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
else
  TAXONOMY_COUNTS=$(sql "SELECT CONCAT('{\"vocabulary\":\"', vid, '\",\"count\":', COUNT(*), '}')
                         FROM taxonomy_term_field_data GROUP BY vid;" \
    | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
fi
[[ -z "$TAXONOMY_COUNTS" || "$TAXONOMY_COUNTS" == "[]" ]] && TAXONOMY_COUNTS="[]"

# --- Media counts (D8+ only, media module) ------------------------------------
MEDIA_COUNTS="[]"
if [[ "$MAJOR" != "7" ]]; then
  MEDIA_COUNTS=$(sql "SELECT CONCAT('{\"bundle\":\"', bundle, '\",\"count\":', COUNT(*), '}')
                      FROM media_field_data GROUP BY bundle;" 2>/dev/null \
    | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
fi
[[ -z "$MEDIA_COUNTS" || "$MEDIA_COUNTS" == "[]" ]] && MEDIA_COUNTS="[]"

# --- User counts --------------------------------------------------------------
if [[ "$MAJOR" == "7" ]]; then
  USER_COUNT=$(sql "SELECT COUNT(*) FROM users WHERE uid > 0;" | tail -1)
  ROLE_COUNTS=$(sql "SELECT CONCAT('{\"role\":\"', r.name, '\",\"count\":', COUNT(ur.uid), '}')
                     FROM users_roles ur
                     JOIN role r ON ur.rid = r.rid
                     GROUP BY r.name;" \
    | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
else
  USER_COUNT=$(sql "SELECT COUNT(*) FROM users_field_data WHERE uid > 0;" | tail -1)
  ROLE_COUNTS=$(sql "SELECT CONCAT('{\"role\":\"', roles_target_id, '\",\"count\":', COUNT(*), '}')
                     FROM user__roles GROUP BY roles_target_id;" \
    | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
fi
USER_COUNT="${USER_COUNT:-0}"
[[ -z "$ROLE_COUNTS" || "$ROLE_COUNTS" == "[]" ]] && ROLE_COUNTS="[]"

# --- File counts by scheme ----------------------------------------------------
if [[ "$MAJOR" == "7" ]]; then
  FILE_COUNTS=$(sql "SELECT CONCAT('{\"scheme\":\"', SUBSTRING_INDEX(uri, '://', 1), '\",\"count\":', COUNT(*), '}')
                     FROM file_managed GROUP BY SUBSTRING_INDEX(uri, '://', 1);" \
    | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
else
  FILE_COUNTS=$(sql "SELECT CONCAT('{\"scheme\":\"', SUBSTRING_INDEX(uri, '://', 1), '\",\"count\":', COUNT(*), '}')
                     FROM file_managed GROUP BY SUBSTRING_INDEX(uri, '://', 1);" \
    | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
fi
[[ -z "$FILE_COUNTS" || "$FILE_COUNTS" == "[]" ]] && FILE_COUNTS="[]"

# --- Revision counts ----------------------------------------------------------
NODE_REVISIONS="0"
if [[ "$MAJOR" == "7" ]]; then
  NODE_REVISIONS=$(sql "SELECT COUNT(*) FROM node_revision;" | tail -1 || echo "0")
else
  NODE_REVISIONS=$(sql "SELECT COUNT(*) FROM node_revision;" | tail -1 || echo "0")
fi
NODE_REVISIONS="${NODE_REVISIONS:-0}"

# --- Multilingual status ------------------------------------------------------
MULTILINGUAL="false"
LANGUAGES="[]"
if [[ "$MAJOR" == "7" ]]; then
  LANG_COUNT=$(sql "SELECT COUNT(*) FROM languages WHERE enabled = 1;" | tail -1 || echo "1")
  if [[ "$LANG_COUNT" -gt 1 ]] 2>/dev/null; then
    MULTILINGUAL="true"
    LANGUAGES=$(sql "SELECT CONCAT('\"', language, '\"') FROM languages WHERE enabled = 1;" \
      | paste -sd',' - | sed 's/^/[/;s/$/]/' || echo "[]")
  fi
else
  # D9+: check config for language.entity.* or use drush
  LANG_LIST=$(drush language:list --format=json 2>/dev/null || echo "{}")
  LANG_KEYS=$(echo "$LANG_LIST" | (jq -r 'keys[]' 2>/dev/null || true))
  LANG_ARRAY=""
  for l in $LANG_KEYS; do
    LANG_ARRAY="${LANG_ARRAY:+$LANG_ARRAY,}\"$l\""
  done
  if [[ -n "$LANG_ARRAY" ]]; then
    LANGUAGES="[$LANG_ARRAY]"
    COUNT=$(echo "$LANG_KEYS" | wc -w | tr -d ' ')
    [[ "$COUNT" -gt 1 ]] && MULTILINGUAL="true"
  fi
fi

##############################################################################
# Assemble JSON
##############################################################################

JSON=$(cat <<ENDJSON
{
  "audit_date": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "site_uri": "$SITE_URI",
  "drupal_version": "$DRUPAL_VERSION",
  "drupal_major": "$MAJOR",
  "php_version": "$PHP_VERSION",
  "database": {
    "driver": "$DB_DRIVER",
    "name": "$DB_NAME",
    "size": $DB_SIZE
  },
  "files_path": "$FILES_PATH",
  "enabled_modules": $MODULES_JSON,
  "content_counts": $CONTENT_COUNTS,
  "taxonomy_counts": $TAXONOMY_COUNTS,
  "media_counts": $MEDIA_COUNTS,
  "users": {
    "total": $USER_COUNT,
    "by_role": $ROLE_COUNTS
  },
  "files_by_scheme": $FILE_COUNTS,
  "node_revisions": $NODE_REVISIONS,
  "multilingual": $MULTILINGUAL,
  "languages": $LANGUAGES
}
ENDJSON
)

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  echo "$JSON" | json_fmt > "$OUTPUT_DIR/audit.json"
  echo "Audit written to $OUTPUT_DIR/audit.json" >&2
else
  echo "$JSON" | json_fmt
fi
