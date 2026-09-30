#!/usr/bin/env bash
# export-blocks.sh — Export custom block content entities + block placement config
# Outputs JSON.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export custom block content and block placement configuration from Drupal.

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
# Custom Block Content
# ============================================================================

BLOCKS="["
FIRST_B=true

if [[ "$MAJOR" == "7" ]]; then
  # D7: block_custom table stores custom block content
  BLOCKS_RAW=$(sql "SELECT bid, info, body, format FROM block_custom ORDER BY bid;" 2>/dev/null || true)

  while IFS=$'\t' read -r BID INFO BODY FMT; do
    [[ -z "$BID" ]] && continue
    INFO_ESC=$(json_escape "$INFO")
    BODY_ESC=$(json_escape "$BODY")
    FMT_ESC=$(json_escape "${FMT:-}")

    [[ "$FIRST_B" == true ]] && FIRST_B=false || BLOCKS="$BLOCKS,"
    BLOCKS="$BLOCKS{\"bid\":$BID,\"info\":\"$INFO_ESC\",\"body\":\"$BODY_ESC\",\"format\":\"$FMT_ESC\"}"
  done <<< "$BLOCKS_RAW"

else
  # D9+: block_content_field_data table for custom block entities
  BLOCKS_RAW=$(sql "
    SELECT id, revision_id, type, info, langcode, status
    FROM block_content_field_data
    WHERE default_langcode = 1
    ORDER BY id;" 2>/dev/null || true)

  while IFS=$'\t' read -r BID BREV BTYPE BINFO BLANG BSTATUS; do
    [[ -z "$BID" ]] && continue
    BINFO_ESC=$(json_escape "$BINFO")

    # Get the body field if it exists
    BODY=""
    BODY_RAW=$(sql "SELECT body_value, body_format FROM block_content__body WHERE entity_id = $BID LIMIT 1;" 2>/dev/null || true)
    if [[ -n "$BODY_RAW" ]]; then
      BODY_VAL=$(echo "$BODY_RAW" | cut -f1)
      BODY_FMT=$(echo "$BODY_RAW" | cut -f2)
      BODY_VAL_ESC=$(json_escape "$BODY_VAL")
      BODY_FMT_ESC=$(json_escape "$BODY_FMT")
      BODY=",\"body\":\"$BODY_VAL_ESC\",\"body_format\":\"$BODY_FMT_ESC\""
    fi

    [[ "$FIRST_B" == true ]] && FIRST_B=false || BLOCKS="$BLOCKS,"
    BLOCKS="$BLOCKS{\"id\":$BID,\"revision_id\":${BREV:-0},\"type\":\"$BTYPE\",\"info\":\"$BINFO_ESC\",\"langcode\":\"${BLANG:-en}\",\"status\":${BSTATUS:-1}$BODY}"
  done <<< "$BLOCKS_RAW"
fi

BLOCKS="$BLOCKS]"

# ============================================================================
# Block Placements (config entities in D9+, block table in D7)
# ============================================================================

PLACEMENTS="["
FIRST_P=true

if [[ "$MAJOR" == "7" ]]; then
  # D7: block table stores placement config
  PLACEMENTS_RAW=$(sql "
    SELECT module, delta, theme, status, weight, region, title, pages, visibility
    FROM block
    WHERE status = 1
    ORDER BY theme, region, weight;" 2>/dev/null || true)

  while IFS=$'\t' read -r PMOD PDELTA PTHEME PSTATUS PWEIGHT PREGION PTITLE PPAGES PVIS; do
    [[ -z "$PMOD" ]] && continue
    PTITLE_ESC=$(json_escape "$PTITLE")
    PPAGES_ESC=$(json_escape "$PPAGES")

    [[ "$FIRST_P" == true ]] && FIRST_P=false || PLACEMENTS="$PLACEMENTS,"
    PLACEMENTS="$PLACEMENTS{\"module\":\"$PMOD\",\"delta\":\"$PDELTA\",\"theme\":\"$PTHEME\",\"weight\":${PWEIGHT:-0},\"region\":\"$PREGION\",\"title\":\"$PTITLE_ESC\",\"pages\":\"$PPAGES_ESC\",\"visibility\":${PVIS:-0}}"
  done <<< "$PLACEMENTS_RAW"

else
  # D9+: block placement configs are block.block.*
  BLOCK_CONFIGS=$(drush config:list --format=list 2>/dev/null | grep '^block\.block\.' || true)

  for BCONFIG in $BLOCK_CONFIGS; do
    BCONFIG=$(echo "$BCONFIG" | tr -d '[:space:]')
    [[ -z "$BCONFIG" ]] && continue

    BLOCK_JSON=$(drush config:get "$BCONFIG" --format=json 2>/dev/null || echo "{}")

    [[ "$FIRST_P" == true ]] && FIRST_P=false || PLACEMENTS="$PLACEMENTS,"
    PLACEMENTS="$PLACEMENTS$BLOCK_JSON"
  done
fi

PLACEMENTS="$PLACEMENTS]"

# ============================================================================
# Final output
# ============================================================================

RESULT="{\"custom_blocks\":$BLOCKS,\"placements\":$PLACEMENTS}"

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  echo "$RESULT" | json_fmt > "$OUTPUT_DIR/blocks.json"
  echo "Blocks exported to $OUTPUT_DIR/blocks.json" >&2
else
  echo "$RESULT" | json_fmt
fi
