#!/usr/bin/env bash
# export-users.sh — Export users with roles and custom fields (EXCLUDING password hashes)
# Outputs JSON.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export Drupal users with roles and profile fields.
Password hashes are explicitly excluded for security.

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

RESULT="["
FIRST=true

if [[ "$MAJOR" == "7" ]]; then
  # D7: users table — explicitly exclude pass column
  USERS_RAW=$(sql "
    SELECT uid, name, mail, status, created, access, login, timezone
    FROM users
    WHERE uid > 0
    ORDER BY uid;")

  while IFS=$'\t' read -r UID UNAME MAIL STATUS CREATED ACCESS LOGIN TZ; do
    [[ -z "$UID" ]] && continue

    UNAME_ESC=$(json_escape "$UNAME")
    MAIL_ESC=$(json_escape "$MAIL")
    TZ_ESC=$(json_escape "${TZ:-}")

    # Get roles for this user
    ROLES=$(sql "SELECT r.name FROM users_roles ur JOIN role r ON ur.rid = r.rid WHERE ur.uid = $UID;" \
      | while read -r ROLE; do echo -n "\"$(json_escape "$ROLE")\","; done \
      | sed 's/,$//')
    ROLES="[${ROLES:-}]"

    [[ "$FIRST" == true ]] && FIRST=false || RESULT="$RESULT,"
    RESULT="$RESULT{\"uid\":$UID,\"name\":\"$UNAME_ESC\",\"mail\":\"$MAIL_ESC\",\"status\":${STATUS:-0},\"created\":${CREATED:-0},\"last_access\":${ACCESS:-0},\"last_login\":${LOGIN:-0},\"timezone\":\"$TZ_ESC\",\"roles\":$ROLES}"

  done <<< "$USERS_RAW"

else
  # D9+: users_field_data table — explicitly exclude pass column
  USERS_RAW=$(sql "
    SELECT uid, name, mail, status, created, access, login, timezone, langcode, preferred_langcode
    FROM users_field_data
    WHERE uid > 0 AND default_langcode = 1
    ORDER BY uid;")

  while IFS=$'\t' read -r UID UNAME MAIL STATUS CREATED ACCESS LOGIN TZ LANG PREF_LANG; do
    [[ -z "$UID" ]] && continue

    UNAME_ESC=$(json_escape "$UNAME")
    MAIL_ESC=$(json_escape "$MAIL")
    TZ_ESC=$(json_escape "${TZ:-}")

    # Get roles from user__roles table
    ROLES=$(sql "SELECT roles_target_id FROM user__roles WHERE entity_id = $UID;" \
      | while read -r ROLE; do echo -n "\"$(json_escape "$ROLE")\","; done \
      | sed 's/,$//')
    ROLES="[${ROLES:-}]"

    # Check for custom user field tables (user__field_*)
    CUSTOM_FIELDS="{}"
    FIELD_TABLES=$(sql "SHOW TABLES LIKE 'user__field_%';" 2>/dev/null || true)
    if [[ -n "$FIELD_TABLES" ]]; then
      CF="{"
      CF_FIRST=true
      for FTABLE in $FIELD_TABLES; do
        FTABLE=$(echo "$FTABLE" | tr -d '[:space:]')
        [[ -z "$FTABLE" ]] && continue
        FIELD_NAME="${FTABLE#user__}"

        # Get column names that contain field values (exclude entity_id, bundle, etc.)
        VALUE_COLS=$(sql "SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS
                          WHERE TABLE_NAME = '$FTABLE' AND TABLE_SCHEMA = DATABASE()
                          AND COLUMN_NAME LIKE '${FIELD_NAME}_%';" 2>/dev/null || true)

        if [[ -n "$VALUE_COLS" ]]; then
          # Get the first value column's data for this user
          FIRST_COL=$(echo "$VALUE_COLS" | head -1 | tr -d '[:space:]')
          VAL=$(sql "SELECT $FIRST_COL FROM $FTABLE WHERE entity_id = $UID LIMIT 1;" 2>/dev/null | head -1 || true)
          if [[ -n "$VAL" ]]; then
            VAL_ESC=$(json_escape "$VAL")
            [[ "$CF_FIRST" == true ]] && CF_FIRST=false || CF="$CF,"
            CF="$CF\"$FIELD_NAME\":\"$VAL_ESC\""
          fi
        fi
      done
      CF="$CF}"
      CUSTOM_FIELDS="$CF"
    fi

    [[ "$FIRST" == true ]] && FIRST=false || RESULT="$RESULT,"
    RESULT="$RESULT{\"uid\":$UID,\"name\":\"$UNAME_ESC\",\"mail\":\"$MAIL_ESC\",\"status\":${STATUS:-0},\"created\":${CREATED:-0},\"last_access\":${ACCESS:-0},\"last_login\":${LOGIN:-0},\"timezone\":\"$TZ_ESC\",\"langcode\":\"${LANG:-en}\",\"preferred_langcode\":\"${PREF_LANG:-en}\",\"roles\":$ROLES,\"custom_fields\":$CUSTOM_FIELDS}"

  done <<< "$USERS_RAW"
fi

RESULT="$RESULT]"

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  echo "$RESULT" | json_fmt > "$OUTPUT_DIR/users.json"
  echo "Users exported to $OUTPUT_DIR/users.json" >&2
else
  echo "$RESULT" | json_fmt
fi
