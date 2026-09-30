#!/usr/bin/env bash
# export-taxonomies.sh — Export vocabularies + all terms with hierarchy
# Uses drush sql:query for term data and parent relationships. Outputs JSON.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export taxonomy vocabularies and all terms with hierarchy from Drupal.

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

# Escape double quotes and backslashes for safe JSON embedding
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

if [[ "$MAJOR" == "7" ]]; then
  # D7: taxonomy_vocabulary, taxonomy_term_data, taxonomy_term_hierarchy

  # Get vocabularies
  VOCABS_RAW=$(sql "SELECT vid, machine_name, name, description FROM taxonomy_vocabulary ORDER BY vid;")

  RESULT="["
  FIRST_V=true

  while IFS=$'\t' read -r VID MACHINE_NAME VNAME VDESC; do
    [[ -z "$VID" ]] && continue

    VNAME_ESC=$(json_escape "$VNAME")
    VDESC_ESC=$(json_escape "$VDESC")

    # Get all terms for this vocabulary with parent info
    # D7 uses taxonomy_term_hierarchy table for parent
    TERMS_RAW=$(sql "
      SELECT t.tid, t.name, t.weight, COALESCE(h.parent, 0) AS parent_tid
      FROM taxonomy_term_data t
      LEFT JOIN taxonomy_term_hierarchy h ON t.tid = h.tid
      WHERE t.vid = $VID
      ORDER BY t.weight, t.name;")

    TERMS="["
    FIRST_T=true
    while IFS=$'\t' read -r TID TNAME TWEIGHT PARENT_TID; do
      [[ -z "$TID" ]] && continue
      TNAME_ESC=$(json_escape "$TNAME")
      [[ "$FIRST_T" == true ]] && FIRST_T=false || TERMS="$TERMS,"
      TERMS="$TERMS{\"tid\":$TID,\"name\":\"$TNAME_ESC\",\"weight\":$TWEIGHT,\"parent_tid\":${PARENT_TID:-0}}"
    done <<< "$TERMS_RAW"
    TERMS="$TERMS]"

    [[ "$FIRST_V" == true ]] && FIRST_V=false || RESULT="$RESULT,"
    RESULT="$RESULT{\"vid\":\"$MACHINE_NAME\",\"name\":\"$VNAME_ESC\",\"description\":\"$VDESC_ESC\",\"terms\":$TERMS}"

  done <<< "$VOCABS_RAW"

  RESULT="$RESULT]"

else
  # D9+: taxonomy_term_field_data, taxonomy_term__parent

  # Get vocabulary config names
  VOCAB_IDS=$(sql "SELECT DISTINCT vid FROM taxonomy_term_field_data ORDER BY vid;" || true)

  # Also get vocab labels from config
  RESULT="["
  FIRST_V=true

  # Get all vocabulary machine names from the taxonomy tables
  if [[ -z "$VOCAB_IDS" ]]; then
    # Try config list
    VOCAB_IDS=$(drush config:list --format=list 2>/dev/null \
      | grep '^taxonomy\.vocabulary\.' \
      | sed 's/^taxonomy\.vocabulary\.//' || true)
  fi

  for VID in $VOCAB_IDS; do
    VID=$(echo "$VID" | tr -d '[:space:]')
    [[ -z "$VID" ]] && continue

    # Get vocab label from config
    VLABEL=$(drush config:get "taxonomy.vocabulary.$VID" label 2>/dev/null | sed "s/^.*: '//" | sed "s/'$//" || echo "$VID")
    VLABEL_ESC=$(json_escape "$VLABEL")

    # Get terms with parent relationships
    # D9+ stores parents in taxonomy_term__parent table
    TERMS_RAW=$(sql "
      SELECT t.tid, t.name, t.weight,
             COALESCE(p.parent_target_id, 0) AS parent_tid
      FROM taxonomy_term_field_data t
      LEFT JOIN taxonomy_term__parent p ON t.tid = p.entity_id
      WHERE t.vid = '$VID' AND t.default_langcode = 1
      ORDER BY t.weight, t.name;")

    TERMS="["
    FIRST_T=true
    while IFS=$'\t' read -r TID TNAME TWEIGHT PARENT_TID; do
      [[ -z "$TID" ]] && continue
      TNAME_ESC=$(json_escape "$TNAME")
      [[ "$FIRST_T" == true ]] && FIRST_T=false || TERMS="$TERMS,"
      TERMS="$TERMS{\"tid\":$TID,\"name\":\"$TNAME_ESC\",\"weight\":${TWEIGHT:-0},\"parent_tid\":${PARENT_TID:-0}}"
    done <<< "$TERMS_RAW"
    TERMS="$TERMS]"

    [[ "$FIRST_V" == true ]] && FIRST_V=false || RESULT="$RESULT,"
    RESULT="$RESULT{\"vid\":\"$VID\",\"name\":\"$VLABEL_ESC\",\"terms\":$TERMS}"
  done

  RESULT="$RESULT]"
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  echo "$RESULT" | json_fmt > "$OUTPUT_DIR/taxonomies.json"
  echo "Taxonomies exported to $OUTPUT_DIR/taxonomies.json" >&2
else
  echo "$RESULT" | json_fmt
fi
