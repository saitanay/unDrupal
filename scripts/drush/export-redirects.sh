#!/usr/bin/env bash
# export-redirects.sh — Export redirect module data (source, redirect, status_code)
# Outputs JSON and optionally nginx/apache/netlify redirect formats.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export Drupal redirect module data (requires the redirect module to be enabled).

Options:
  --output-dir DIR   Write output files to DIR instead of stdout
  --format FORMAT    Output format: json (default), nginx, apache, netlify, all
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

# Check if the redirect table exists
TABLE_EXISTS=$(sql "SHOW TABLES LIKE 'redirect';" 2>/dev/null || true)
if [[ -z "$TABLE_EXISTS" ]]; then
  echo "Error: redirect table not found. Is the redirect module enabled?" >&2
  echo "[]" | json_fmt
  exit 1
fi

declare -a R_SOURCES R_REDIRECTS R_CODES R_LANGUAGES

if [[ "$MAJOR" == "7" ]]; then
  # D7: redirect table has source, redirect, status_code, language columns
  REDIR_RAW=$(sql "SELECT source, redirect, status_code, language FROM redirect WHERE status = 1 ORDER BY source;")

  while IFS=$'\t' read -r SRC REDIR CODE LANG; do
    [[ -z "$SRC" ]] && continue
    R_SOURCES+=("$SRC")
    R_REDIRECTS+=("$REDIR")
    R_CODES+=("${CODE:-301}")
    R_LANGUAGES+=("${LANG:-und}")
  done <<< "$REDIR_RAW"

else
  # D9+: redirect table has redirect_source__path, redirect_redirect__uri, status_code, language
  REDIR_RAW=$(sql "SELECT redirect_source__path, redirect_redirect__uri, status_code, language
                    FROM redirect ORDER BY redirect_source__path;")

  while IFS=$'\t' read -r SRC REDIR CODE LANG; do
    [[ -z "$SRC" ]] && continue
    R_SOURCES+=("$SRC")
    R_REDIRECTS+=("$REDIR")
    R_CODES+=("${CODE:-301}")
    R_LANGUAGES+=("${LANG:-und}")
  done <<< "$REDIR_RAW"
fi

TOTAL=${#R_SOURCES[@]:-0}
echo "Found $TOTAL redirects." >&2

# --- Build JSON ---------------------------------------------------------------
build_json() {
  local JSON="["
  local FIRST=true
  for i in $(seq 0 $((TOTAL - 1))); do
    local SRC_ESC REDIR_ESC
    SRC_ESC=$(json_escape "${R_SOURCES[$i]}")
    REDIR_ESC=$(json_escape "${R_REDIRECTS[$i]}")
    [[ "$FIRST" == true ]] && FIRST=false || JSON="$JSON,"
    JSON="$JSON{\"source\":\"$SRC_ESC\",\"redirect\":\"$REDIR_ESC\",\"status_code\":${R_CODES[$i]},\"language\":\"${R_LANGUAGES[$i]}\"}"
  done
  JSON="$JSON]"
  echo "$JSON"
}

# --- Build nginx redirects ----------------------------------------------------
build_nginx() {
  for i in $(seq 0 $((TOTAL - 1))); do
    local CODE=${R_CODES[$i]}
    local DIRECTIVE="permanent"
    [[ "$CODE" == "302" ]] && DIRECTIVE="redirect"
    echo "rewrite ^/${R_SOURCES[$i]}$ ${R_REDIRECTS[$i]} $DIRECTIVE;"
  done
}

# --- Build apache redirects ---------------------------------------------------
build_apache() {
  for i in $(seq 0 $((TOTAL - 1))); do
    echo "Redirect ${R_CODES[$i]} /${R_SOURCES[$i]} ${R_REDIRECTS[$i]}"
  done
}

# --- Build netlify _redirects -------------------------------------------------
build_netlify() {
  for i in $(seq 0 $((TOTAL - 1))); do
    # Netlify format: /from /to status_code
    echo "/${R_SOURCES[$i]} ${R_REDIRECTS[$i]} ${R_CODES[$i]}"
  done
}

# --- Output -------------------------------------------------------------------
if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"

  if [[ "$FORMAT" == "json" || "$FORMAT" == "all" ]]; then
    build_json | json_fmt > "$OUTPUT_DIR/redirects.json"
    echo "Written: $OUTPUT_DIR/redirects.json" >&2
  fi
  if [[ "$FORMAT" == "nginx" || "$FORMAT" == "all" ]]; then
    build_nginx > "$OUTPUT_DIR/redirects-nginx.conf"
    echo "Written: $OUTPUT_DIR/redirects-nginx.conf" >&2
  fi
  if [[ "$FORMAT" == "apache" || "$FORMAT" == "all" ]]; then
    build_apache > "$OUTPUT_DIR/redirects-apache.conf"
    echo "Written: $OUTPUT_DIR/redirects-apache.conf" >&2
  fi
  if [[ "$FORMAT" == "netlify" || "$FORMAT" == "all" ]]; then
    build_netlify > "$OUTPUT_DIR/_redirects"
    echo "Written: $OUTPUT_DIR/_redirects" >&2
  fi
else
  case "$FORMAT" in
    json) build_json | json_fmt ;;
    nginx) build_nginx ;;
    apache) build_apache ;;
    netlify) build_netlify ;;
    all)
      echo "=== JSON ===" >&2
      build_json | json_fmt
      echo ""
      echo "=== NGINX ===" >&2
      build_nginx
      echo ""
      echo "=== APACHE ===" >&2
      build_apache
      echo ""
      echo "=== NETLIFY ===" >&2
      build_netlify
      ;;
    *) echo "Unknown format: $FORMAT" >&2; exit 1 ;;
  esac
fi
