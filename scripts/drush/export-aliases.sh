#!/usr/bin/env bash
# export-aliases.sh — Export all path aliases from Drupal
# Supports D7 (url_alias table), D9+ (path_alias table).
# Outputs JSON and optionally nginx/apache redirect format.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export all URL path aliases from Drupal.

Options:
  --output-dir DIR   Write output files to DIR instead of stdout
  --format FORMAT    Output format: json (default), nginx, apache, all
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
FORMAT="json"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --format) FORMAT="$2"; shift 2 ;;
    --help) usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

require_drush

MAJOR=$(detect_major)

# Collect aliases into arrays for multi-format output
declare -a SOURCES ALIASES LANGCODES

if [[ "$MAJOR" == "7" ]]; then
  # D7/D8: url_alias table (source, alias, language)
  ALIAS_RAW=$(sql "SELECT source, alias, language FROM url_alias ORDER BY alias;")

  while IFS=$'\t' read -r SRC ALIAS LANG; do
    [[ -z "$SRC" ]] && continue
    SOURCES+=("$SRC")
    ALIASES+=("$ALIAS")
    LANGCODES+=("${LANG:-und}")
  done <<< "$ALIAS_RAW"

else
  # D9+: path_alias table (path, alias, langcode)
  ALIAS_RAW=$(sql "SELECT path, alias, langcode FROM path_alias WHERE status = 1 ORDER BY alias;")

  while IFS=$'\t' read -r SRC ALIAS LANG; do
    [[ -z "$SRC" ]] && continue
    SOURCES+=("$SRC")
    ALIASES+=("$ALIAS")
    LANGCODES+=("${LANG:-und}")
  done <<< "$ALIAS_RAW"
fi

TOTAL=${#SOURCES[@]}
echo "Found $TOTAL path aliases." >&2

# --- Build JSON ---------------------------------------------------------------
build_json() {
  local JSON="["
  local FIRST=true
  for i in $(seq 0 $((TOTAL - 1))); do
    local SRC_ESC ALIAS_ESC
    SRC_ESC=$(json_escape "${SOURCES[$i]}")
    ALIAS_ESC=$(json_escape "${ALIASES[$i]}")
    [[ "$FIRST" == true ]] && FIRST=false || JSON="$JSON,"
    JSON="$JSON{\"source\":\"$SRC_ESC\",\"alias\":\"$ALIAS_ESC\",\"langcode\":\"${LANGCODES[$i]}\"}"
  done
  JSON="$JSON]"
  echo "$JSON"
}

# --- Build nginx redirects ----------------------------------------------------
build_nginx() {
  for i in $(seq 0 $((TOTAL - 1))); do
    # Redirect from old Drupal internal path to the alias
    echo "rewrite ^${SOURCES[$i]}$ ${ALIASES[$i]} permanent;"
  done
}

# --- Build apache redirects ---------------------------------------------------
build_apache() {
  for i in $(seq 0 $((TOTAL - 1))); do
    echo "Redirect 301 ${SOURCES[$i]} ${ALIASES[$i]}"
  done
}

# --- Output -------------------------------------------------------------------
if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"

  if [[ "$FORMAT" == "json" || "$FORMAT" == "all" ]]; then
    build_json | json_fmt > "$OUTPUT_DIR/aliases.json"
    echo "Written: $OUTPUT_DIR/aliases.json" >&2
  fi
  if [[ "$FORMAT" == "nginx" || "$FORMAT" == "all" ]]; then
    build_nginx > "$OUTPUT_DIR/aliases-nginx.conf"
    echo "Written: $OUTPUT_DIR/aliases-nginx.conf" >&2
  fi
  if [[ "$FORMAT" == "apache" || "$FORMAT" == "all" ]]; then
    build_apache > "$OUTPUT_DIR/aliases-apache.conf"
    echo "Written: $OUTPUT_DIR/aliases-apache.conf" >&2
  fi
else
  case "$FORMAT" in
    json) build_json | json_fmt ;;
    nginx) build_nginx ;;
    apache) build_apache ;;
    all)
      echo "=== JSON ===" >&2
      build_json | json_fmt
      echo ""
      echo "=== NGINX ===" >&2
      build_nginx
      echo ""
      echo "=== APACHE ===" >&2
      build_apache
      ;;
    *) echo "Unknown format: $FORMAT" >&2; exit 1 ;;
  esac
fi
