#!/usr/bin/env bash
# export-menus.sh — Export menu definitions and all menu links with tree structure
# Outputs JSON.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export Drupal menu definitions and all menu links with tree structure.

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

if [[ "$MAJOR" == "7" ]]; then
  # D7: menu_custom table for definitions, menu_links for link tree

  # Menu definitions
  MENUS_RAW=$(sql "SELECT menu_name, title, description FROM menu_custom ORDER BY menu_name;")

  RESULT="["
  FIRST_M=true

  while IFS=$'\t' read -r MENU_NAME TITLE DESC; do
    [[ -z "$MENU_NAME" ]] && continue

    TITLE_ESC=$(json_escape "$TITLE")
    DESC_ESC=$(json_escape "$DESC")

    # Menu links for this menu, ordered by weight for tree reconstruction
    # p1..p9 columns represent the materialized path in D7
    LINKS_RAW=$(sql "
      SELECT mlid, plid, link_path, link_title, weight, hidden, depth
      FROM menu_links
      WHERE menu_name = '$MENU_NAME' AND hidden = 0
      ORDER BY p1, p2, p3, p4, p5, p6, p7, p8, p9;")

    LINKS="["
    FIRST_L=true
    while IFS=$'\t' read -r MLID PLID LINK_PATH LINK_TITLE WEIGHT HIDDEN DEPTH; do
      [[ -z "$MLID" ]] && continue
      LINK_TITLE_ESC=$(json_escape "$LINK_TITLE")
      LINK_PATH_ESC=$(json_escape "$LINK_PATH")
      [[ "$FIRST_L" == true ]] && FIRST_L=false || LINKS="$LINKS,"
      LINKS="$LINKS{\"mlid\":$MLID,\"parent_mlid\":${PLID:-0},\"path\":\"$LINK_PATH_ESC\",\"title\":\"$LINK_TITLE_ESC\",\"weight\":${WEIGHT:-0},\"depth\":${DEPTH:-0}}"
    done <<< "$LINKS_RAW"
    LINKS="$LINKS]"

    [[ "$FIRST_M" == true ]] && FIRST_M=false || RESULT="$RESULT,"
    RESULT="$RESULT{\"menu_name\":\"$MENU_NAME\",\"title\":\"$TITLE_ESC\",\"description\":\"$DESC_ESC\",\"links\":$LINKS}"

  done <<< "$MENUS_RAW"

  RESULT="$RESULT]"

else
  # D9+: menu config entities + menu_link_content_data table

  # Get menu config names
  MENU_IDS=$(drush config:list --format=list 2>/dev/null | grep '^system\.menu\.' | sed 's/^system\.menu\.//' || true)

  RESULT="["
  FIRST_M=true

  for MENU_ID in $MENU_IDS; do
    MENU_ID=$(echo "$MENU_ID" | tr -d '[:space:]')
    [[ -z "$MENU_ID" ]] && continue

    # Get menu label/description from config
    MENU_LABEL=$(drush config:get "system.menu.$MENU_ID" label 2>/dev/null | sed "s/^.*: '//" | sed "s/'$//" || echo "$MENU_ID")
    MENU_DESC=$(drush config:get "system.menu.$MENU_ID" description 2>/dev/null | sed "s/^.*: '//" | sed "s/'$//" || echo "")
    MENU_LABEL_ESC=$(json_escape "$MENU_LABEL")
    MENU_DESC_ESC=$(json_escape "$MENU_DESC")

    # Get menu links from menu_link_content_data table
    LINKS_RAW=$(sql "
      SELECT mlc.id, mlc.title, mlc.link__uri, mlc.link__options, mlc.weight, mlc.enabled,
             mlt.depth, mlt.parent
      FROM menu_link_content_data mlc
      LEFT JOIN menu_tree mlt ON mlt.id = CONCAT('menu_link_content:', mlc.uuid)
      WHERE mlc.menu_name = '$MENU_ID' AND mlc.default_langcode = 1
      ORDER BY COALESCE(mlt.depth, 0), mlc.weight;" 2>/dev/null || true)

    # Fallback: if menu_tree join fails, query menu_link_content_data alone
    if [[ -z "$LINKS_RAW" ]]; then
      LINKS_RAW=$(sql "
        SELECT id, title, link__uri, link__options, weight, enabled, 0, ''
        FROM menu_link_content_data
        WHERE menu_name = '$MENU_ID' AND default_langcode = 1
        ORDER BY weight;" 2>/dev/null || true)
    fi

    LINKS="["
    FIRST_L=true
    while IFS=$'\t' read -r LID LTITLE LURI LOPTS LWEIGHT LENABLED LDEPTH LPARENT; do
      [[ -z "$LID" ]] && continue
      LTITLE_ESC=$(json_escape "$LTITLE")
      LURI_ESC=$(json_escape "$LURI")
      LPARENT_ESC=$(json_escape "${LPARENT:-}")
      [[ "$FIRST_L" == true ]] && FIRST_L=false || LINKS="$LINKS,"
      LINKS="$LINKS{\"id\":$LID,\"title\":\"$LTITLE_ESC\",\"uri\":\"$LURI_ESC\",\"weight\":${LWEIGHT:-0},\"enabled\":${LENABLED:-1},\"depth\":${LDEPTH:-0},\"parent\":\"$LPARENT_ESC\"}"
    done <<< "$LINKS_RAW"
    LINKS="$LINKS]"

    [[ "$FIRST_M" == true ]] && FIRST_M=false || RESULT="$RESULT,"
    RESULT="$RESULT{\"menu_name\":\"$MENU_ID\",\"label\":\"$MENU_LABEL_ESC\",\"description\":\"$MENU_DESC_ESC\",\"links\":$LINKS}"
  done

  RESULT="$RESULT]"
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  echo "$RESULT" | json_fmt > "$OUTPUT_DIR/menus.json"
  echo "Menus exported to $OUTPUT_DIR/menus.json" >&2
else
  echo "$RESULT" | json_fmt
fi
