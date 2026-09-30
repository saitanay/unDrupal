#!/usr/bin/env bash
# export-views.sh — Export all Views as YAML files
# Iterates views.view.* configs and writes each to a separate YAML file.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export all Drupal Views as individual YAML files.

Options:
  --output-dir DIR   Directory to write YAML files into (default: ./views-export)
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

OUTPUT_DIR="./views-export"

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
  # D7: Views are stored in the views_view table, not config
  echo "Drupal 7 detected — Views are database-stored." >&2
  echo "Attempting to export via drush views:list and ctools export..." >&2

  mkdir -p "$OUTPUT_DIR"

  # Try drush vde (views-dev-export) if available, otherwise dump from DB
  if drush help views-dev-export &>/dev/null 2>&1; then
    VIEWS=$(drush views:list --format=list 2>/dev/null || true)
    for VIEW in $VIEWS; do
      drush views-dev-export "$VIEW" > "$OUTPUT_DIR/${VIEW}.view.php" 2>/dev/null || true
      echo "Exported: $VIEW" >&2
    done
  else
    # Fallback: dump the raw view records
    drush sql:query "SELECT vid, name, description, tag, human_name FROM views_view ORDER BY name;" \
      > "$OUTPUT_DIR/d7-views-list.txt" 2>/dev/null || true
    echo "D7 views list written to $OUTPUT_DIR/d7-views-list.txt" >&2
    echo "Install views_dev module for full PHP export, or use Features." >&2
  fi
  exit 0
fi

# D9+: views are config entities
mkdir -p "$OUTPUT_DIR"

# List all views.view.* config names
VIEW_CONFIGS=$(drush config:list --format=list 2>/dev/null | grep '^views\.view\.' || true)

if [[ -z "$VIEW_CONFIGS" ]]; then
  echo "No views found." >&2
  exit 0
fi

COUNT=0
for VIEW_CONFIG in $VIEW_CONFIGS; do
  # Extract the view machine name (views.view.MACHINE_NAME)
  VIEW_NAME="${VIEW_CONFIG#views.view.}"

  # Export the config as YAML
  drush config:get "$VIEW_CONFIG" --format=yaml > "$OUTPUT_DIR/${VIEW_NAME}.yml" 2>/dev/null || {
    echo "Warning: failed to export $VIEW_CONFIG" >&2
    continue
  }

  COUNT=$((COUNT + 1))
  echo "Exported: $VIEW_NAME" >&2
done

echo "Exported $COUNT views to $OUTPUT_DIR/" >&2
