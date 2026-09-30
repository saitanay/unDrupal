#!/usr/bin/env bash
# export-metatags.sh — Export metatag defaults + per-entity metatag overrides
# Outputs JSON.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export metatag configuration (defaults and per-entity overrides) from Drupal.
Requires the metatag module to be enabled.

Options:
  --output-dir DIR   Write JSON to DIR instead of stdout
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

json_fmt() {
  if command -v jq &>/dev/null; then
    jq .
  else
    cat
  fi
}

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/}"
  s="${s//$'\t'/\\t}"
  echo -n "$s"
}

detect_major() {
  local ver
  ver=$(drush status --field=drupal-version 2>/dev/null || true)
  echo "${ver%%.*}"
}

sql() {
  drush sql:query "$1" 2>/dev/null || true
}

OUTPUT_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --help) usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

require_drush

MAJOR=$(detect_major)

# ============================================================================
# Metatag Defaults (config)
# ============================================================================

DEFAULTS="[]"

if [[ "$MAJOR" == "7" ]]; then
  # D7: metatag_config table stores default metatag patterns
  TABLE_EXISTS=$(sql "SHOW TABLES LIKE 'metatag_config';" 2>/dev/null || true)
  if [[ -n "$TABLE_EXISTS" ]]; then
    DEFAULTS_RAW=$(sql "SELECT instance, config FROM metatag_config ORDER BY instance;")

    DEFAULTS="["
    FIRST=true
    while IFS=$'\t' read -r INSTANCE CONFIG; do
      [[ -z "$INSTANCE" ]] && continue
      INSTANCE_ESC=$(json_escape "$INSTANCE")
      CONFIG_ESC=$(json_escape "$CONFIG")

      [[ "$FIRST" == true ]] && FIRST=false || DEFAULTS="$DEFAULTS,"
      DEFAULTS="$DEFAULTS{\"instance\":\"$INSTANCE_ESC\",\"config\":\"$CONFIG_ESC\"}"
    done <<< "$DEFAULTS_RAW"
    DEFAULTS="$DEFAULTS]"
  else
    echo "Warning: metatag_config table not found. Is metatag module enabled?" >&2
  fi

else
  # D9+: metatag defaults are stored as config entities (metatag.metatag_defaults.*)
  DEFAULT_CONFIGS=$(drush config:list --format=list 2>/dev/null | grep '^metatag\.metatag_defaults\.' || true)

  if [[ -n "$DEFAULT_CONFIGS" ]]; then
    DEFAULTS="["
    FIRST=true
    for DCFG in $DEFAULT_CONFIGS; do
      DCFG=$(echo "$DCFG" | tr -d '[:space:]')
      [[ -z "$DCFG" ]] && continue

      CFG_JSON=$(drush config:get "$DCFG" --format=json 2>/dev/null || echo "{}")

      [[ "$FIRST" == true ]] && FIRST=false || DEFAULTS="$DEFAULTS,"
      DEFAULTS="$DEFAULTS$CFG_JSON"
    done
    DEFAULTS="$DEFAULTS]"
  else
    echo "No metatag default configs found. Is metatag module enabled?" >&2
  fi
fi

# ============================================================================
# Per-entity metatag overrides
# ============================================================================

OVERRIDES="[]"

if [[ "$MAJOR" == "7" ]]; then
  # D7: metatag table stores per-entity overrides
  TABLE_EXISTS=$(sql "SHOW TABLES LIKE 'metatag';" 2>/dev/null || true)
  if [[ -n "$TABLE_EXISTS" ]]; then
    # Get count first to warn about large exports
    OVERRIDE_COUNT=$(sql "SELECT COUNT(*) FROM metatag;" | tail -1 || echo "0")
    echo "Found $OVERRIDE_COUNT per-entity metatag overrides." >&2

    OVERRIDES_RAW=$(sql "
      SELECT entity_type, entity_id, revision_id, language, data
      FROM metatag
      ORDER BY entity_type, entity_id;")

    OVERRIDES="["
    FIRST=true
    while IFS=$'\t' read -r ETYPE EID EREV ELANG EDATA; do
      [[ -z "$ETYPE" ]] && continue
      ETYPE_ESC=$(json_escape "$ETYPE")
      EDATA_ESC=$(json_escape "$EDATA")

      [[ "$FIRST" == true ]] && FIRST=false || OVERRIDES="$OVERRIDES,"
      OVERRIDES="$OVERRIDES{\"entity_type\":\"$ETYPE_ESC\",\"entity_id\":${EID:-0},\"revision_id\":${EREV:-0},\"language\":\"${ELANG:-und}\",\"data\":\"$EDATA_ESC\"}"
    done <<< "$OVERRIDES_RAW"
    OVERRIDES="$OVERRIDES]"
  fi

else
  # D9+: per-entity metatags are stored in entity field tables
  # Common tables: node__field_metatag, taxonomy_term__field_metatag, user__field_metatag
  METATAG_TABLES=$(sql "SHOW TABLES LIKE '%__field_metatag%';" 2>/dev/null || true)

  if [[ -n "$METATAG_TABLES" ]]; then
    OVERRIDES="["
    FIRST=true

    for MTABLE in $METATAG_TABLES; do
      MTABLE=$(echo "$MTABLE" | tr -d '[:space:]')
      [[ -z "$MTABLE" ]] && continue

      # Extract entity type from table name (e.g., node__field_metatag -> node)
      ENTITY_TYPE="${MTABLE%%__*}"

      METATAG_RAW=$(sql "
        SELECT entity_id, bundle, field_metatag_value
        FROM $MTABLE
        ORDER BY entity_id;")

      while IFS=$'\t' read -r EID EBUNDLE EVAL; do
        [[ -z "$EID" ]] && continue
        EBUNDLE_ESC=$(json_escape "$EBUNDLE")
        EVAL_ESC=$(json_escape "$EVAL")

        [[ "$FIRST" == true ]] && FIRST=false || OVERRIDES="$OVERRIDES,"
        OVERRIDES="$OVERRIDES{\"entity_type\":\"$ENTITY_TYPE\",\"entity_id\":$EID,\"bundle\":\"$EBUNDLE_ESC\",\"metatags\":\"$EVAL_ESC\"}"
      done <<< "$METATAG_RAW"
    done

    OVERRIDES="$OVERRIDES]"
  else
    echo "No per-entity metatag field tables found." >&2
  fi
fi

# ============================================================================
# Final output
# ============================================================================

RESULT="{\"defaults\":$DEFAULTS,\"overrides\":$OVERRIDES}"

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  echo "$RESULT" | json_fmt > "$OUTPUT_DIR/metatags.json"
  echo "Metatags exported to $OUTPUT_DIR/metatags.json" >&2
else
  echo "$RESULT" | json_fmt
fi
