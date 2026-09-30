#!/usr/bin/env bash
# export-config.sh — Wrapper around drush config:export
# Exports full site configuration to a specified directory.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export Drupal configuration via drush config:export.

Options:
  --output-dir DIR   Directory to export config into (required)
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

detect_major() {
  local ver
  ver=$(drush status --field=drupal-version 2>/dev/null || true)
  echo "${ver%%.*}"
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

if [[ -z "$OUTPUT_DIR" ]]; then
  echo "Error: --output-dir is required." >&2
  usage
fi

MAJOR=$(detect_major)

mkdir -p "$OUTPUT_DIR"

if [[ "$MAJOR" == "7" ]]; then
  # D7 does not have config:export; use Features or dump variables table
  echo "Drupal 7 detected — config:export is not available." >&2
  echo "Exporting variables table as a fallback..." >&2
  drush sql:query "SELECT name, value FROM variable ORDER BY name;" \
    > "$OUTPUT_DIR/d7-variables.txt" 2>/dev/null || true
  echo "Variables exported to $OUTPUT_DIR/d7-variables.txt" >&2
else
  # D8/D9/D10/D11: use config:export
  echo "Exporting configuration to $OUTPUT_DIR ..." >&2
  if drush config:export --destination="$OUTPUT_DIR" -y 2>&1; then
    echo "Configuration exported successfully to $OUTPUT_DIR" >&2
  else
    echo "Error: config:export failed. Check drush status and permissions." >&2
    exit 1
  fi
fi
