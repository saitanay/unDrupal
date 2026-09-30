#!/usr/bin/env bash
# export-content-types.sh — Export content type + field definitions as JSON
# Uses drush config:get for node.type.*, field.storage.*, field.field.* configs.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export content type and field definitions from Drupal.

Options:
  --output-dir DIR   Write JSON files to DIR (one per content type)
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

MAJOR=$(detect_major)

if [[ "$MAJOR" == "7" ]]; then
  # D7: content types live in the node_type table; fields in field_config
  echo "Drupal 7 detected — extracting from database tables." >&2

  # Get content types
  TYPES_JSON=$(drush sql:query "
    SELECT CONCAT('{\"type\":\"', type, '\",\"name\":\"', name, '\",\"description\":\"', REPLACE(description, '\"', '\\\\\"'), '\"}')
    FROM node_type WHERE disabled = 0 ORDER BY type;" 2>/dev/null \
    | paste -sd',' - | sed 's/^/[/;s/$/]/')
  TYPES_JSON="${TYPES_JSON:-[]}"

  # Get fields per bundle
  FIELDS_JSON=$(drush sql:query "
    SELECT CONCAT('{\"field_name\":\"', fc.field_name, '\",\"type\":\"', fc.type,
                  '\",\"bundle\":\"', fci.bundle, '\",\"entity_type\":\"', fci.entity_type,
                  '\",\"required\":', fci.required, '}')
    FROM field_config fc
    JOIN field_config_instance fci ON fc.id = fci.field_id
    WHERE fci.entity_type = 'node' AND fc.active = 1 AND fc.deleted = 0
    ORDER BY fci.bundle, fc.field_name;" 2>/dev/null \
    | paste -sd',' - | sed 's/^/[/;s/$/]/')
  FIELDS_JSON="${FIELDS_JSON:-[]}"

  RESULT="{\"drupal_version\":7,\"content_types\":$TYPES_JSON,\"fields\":$FIELDS_JSON}"

  if [[ -n "$OUTPUT_DIR" ]]; then
    mkdir -p "$OUTPUT_DIR"
    echo "$RESULT" | json_fmt > "$OUTPUT_DIR/content-types.json"
    echo "Written to $OUTPUT_DIR/content-types.json" >&2
  else
    echo "$RESULT" | json_fmt
  fi
  exit 0
fi

# D9+: use config:get for each node.type.* and related field configs

# Collect all content type machine names
TYPES=$(drush config:list --format=list 2>/dev/null | grep '^node\.type\.' | sed 's/^node\.type\.//')

if [[ -z "$TYPES" ]]; then
  echo "No content types found." >&2
  echo "[]" | json_fmt
  exit 0
fi

ALL_TYPES="["
FIRST=true

for TYPE in $TYPES; do
  echo "Processing content type: $TYPE" >&2

  # Get the content type config
  TYPE_CONFIG=$(drush config:get "node.type.$TYPE" --format=json 2>/dev/null || echo "{}")

  # Get field.storage.node.* and field.field.node.$TYPE.* configs
  FIELD_STORAGES="[]"
  FIELD_INSTANCES="[]"

  # Field instances for this bundle
  INSTANCE_NAMES=$(drush config:list --format=list 2>/dev/null \
    | grep "^field\.field\.node\.${TYPE}\." || true)

  INSTANCES="["
  INST_FIRST=true
  for INST_NAME in $INSTANCE_NAMES; do
    INST_CONFIG=$(drush config:get "$INST_NAME" --format=json 2>/dev/null || echo "{}")
    if [[ "$INST_FIRST" == true ]]; then
      INST_FIRST=false
    else
      INSTANCES="$INSTANCES,"
    fi
    INSTANCES="$INSTANCES$INST_CONFIG"
  done
  INSTANCES="$INSTANCES]"

  # Corresponding field storages
  STORAGE_NAMES=""
  for INST_NAME in $INSTANCE_NAMES; do
    # field.field.node.TYPE.FIELD_NAME -> field.storage.node.FIELD_NAME
    FIELD_NAME=$(echo "$INST_NAME" | sed "s/^field\.field\.node\.${TYPE}\.//")
    STORAGE_NAMES="$STORAGE_NAMES field.storage.node.$FIELD_NAME"
  done

  STORAGES="["
  STOR_FIRST=true
  for STOR_NAME in $STORAGE_NAMES; do
    STOR_CONFIG=$(drush config:get "$STOR_NAME" --format=json 2>/dev/null || echo "{}")
    if [[ "$STOR_FIRST" == true ]]; then
      STOR_FIRST=false
    else
      STORAGES="$STORAGES,"
    fi
    STORAGES="$STORAGES$STOR_CONFIG"
  done
  STORAGES="$STORAGES]"

  ENTRY="{\"type_config\":$TYPE_CONFIG,\"field_storages\":$STORAGES,\"field_instances\":$INSTANCES}"

  if [[ "$FIRST" == true ]]; then
    FIRST=false
  else
    ALL_TYPES="$ALL_TYPES,"
  fi
  ALL_TYPES="$ALL_TYPES$ENTRY"
done

ALL_TYPES="$ALL_TYPES]"

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  echo "$ALL_TYPES" | json_fmt > "$OUTPUT_DIR/content-types.json"
  echo "Written to $OUTPUT_DIR/content-types.json" >&2
else
  echo "$ALL_TYPES" | json_fmt
fi
