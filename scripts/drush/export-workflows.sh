#!/usr/bin/env bash
# export-workflows.sh — Export workflow/moderation config and current entity moderation states
# Outputs JSON.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Export content moderation workflows and current entity moderation states from Drupal.
Requires the content_moderation / workflows module (D8+).

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

if [[ "$MAJOR" == "7" ]]; then
  # D7: content moderation via workbench_moderation module
  echo "Drupal 7 detected — checking for workbench_moderation..." >&2

  TABLE_EXISTS=$(sql "SHOW TABLES LIKE 'workbench_moderation_node_history';" 2>/dev/null || true)

  if [[ -z "$TABLE_EXISTS" ]]; then
    echo "Warning: workbench_moderation not found. No workflow data to export." >&2
    RESULT='{"workflows":[],"moderation_states":[],"note":"workbench_moderation not installed"}'
  else
    # Get moderation states
    STATES=$(sql "SELECT name, description, weight FROM workbench_moderation_states ORDER BY weight;" 2>/dev/null || true)
    STATES_JSON="["
    FIRST=true
    while IFS=$'\t' read -r SNAME SDESC SWEIGHT; do
      [[ -z "$SNAME" ]] && continue
      SNAME_ESC=$(json_escape "$SNAME")
      SDESC_ESC=$(json_escape "$SDESC")
      [[ "$FIRST" == true ]] && FIRST=false || STATES_JSON="$STATES_JSON,"
      STATES_JSON="$STATES_JSON{\"name\":\"$SNAME_ESC\",\"description\":\"$SDESC_ESC\",\"weight\":${SWEIGHT:-0}}"
    done <<< "$STATES"
    STATES_JSON="$STATES_JSON]"

    # Get transitions
    TRANSITIONS=$(sql "SELECT from_name, to_name FROM workbench_moderation_transitions ORDER BY from_name;" 2>/dev/null || true)
    TRANSITIONS_JSON="["
    FIRST=true
    while IFS=$'\t' read -r TFROM TTO; do
      [[ -z "$TFROM" ]] && continue
      TFROM_ESC=$(json_escape "$TFROM")
      TTO_ESC=$(json_escape "$TTO")
      [[ "$FIRST" == true ]] && FIRST=false || TRANSITIONS_JSON="$TRANSITIONS_JSON,"
      TRANSITIONS_JSON="$TRANSITIONS_JSON{\"from\":\"$TFROM_ESC\",\"to\":\"$TTO_ESC\"}"
    done <<< "$TRANSITIONS"
    TRANSITIONS_JSON="$TRANSITIONS_JSON]"

    # Current moderation state of each node (latest entry per nid)
    CURRENT_STATES=$(sql "
      SELECT h.nid, h.state, h.published, h.stamp
      FROM workbench_moderation_node_history h
      INNER JOIN (
        SELECT nid, MAX(hid) AS max_hid FROM workbench_moderation_node_history GROUP BY nid
      ) latest ON h.nid = latest.nid AND h.hid = latest.max_hid
      ORDER BY h.nid;" 2>/dev/null || true)

    CURRENT_JSON="["
    FIRST=true
    while IFS=$'\t' read -r CNID CSTATE CPUB CSTAMP; do
      [[ -z "$CNID" ]] && continue
      CSTATE_ESC=$(json_escape "$CSTATE")
      [[ "$FIRST" == true ]] && FIRST=false || CURRENT_JSON="$CURRENT_JSON,"
      CURRENT_JSON="$CURRENT_JSON{\"nid\":$CNID,\"state\":\"$CSTATE_ESC\",\"published\":${CPUB:-0},\"timestamp\":${CSTAMP:-0}}"
    done <<< "$CURRENT_STATES"
    CURRENT_JSON="$CURRENT_JSON]"

    RESULT="{\"states\":$STATES_JSON,\"transitions\":$TRANSITIONS_JSON,\"current_states\":$CURRENT_JSON}"
  fi

else
  # D9+: workflows module + content_moderation

  # Get workflow config entities
  WORKFLOW_CONFIGS=$(drush config:list --format=list 2>/dev/null | grep '^workflows\.workflow\.' || true)

  WORKFLOWS="["
  FIRST_W=true

  if [[ -n "$WORKFLOW_CONFIGS" ]]; then
    for WCFG in $WORKFLOW_CONFIGS; do
      WCFG=$(echo "$WCFG" | tr -d '[:space:]')
      [[ -z "$WCFG" ]] && continue

      WF_JSON=$(drush config:get "$WCFG" --format=json 2>/dev/null || echo "{}")

      [[ "$FIRST_W" == true ]] && FIRST_W=false || WORKFLOWS="$WORKFLOWS,"
      WORKFLOWS="$WORKFLOWS$WF_JSON"
    done
  else
    echo "No workflow configs found. Is the workflows module enabled?" >&2
  fi
  WORKFLOWS="$WORKFLOWS]"

  # Current moderation states from content_moderation_state_field_data
  MODERATION_STATES="[]"
  TABLE_EXISTS=$(sql "SHOW TABLES LIKE 'content_moderation_state_field_data';" 2>/dev/null || true)

  if [[ -n "$TABLE_EXISTS" ]]; then
    MOD_RAW=$(sql "
      SELECT content_entity_type_id, content_entity_id, content_entity_revision_id,
             moderation_state, workflow, langcode
      FROM content_moderation_state_field_data
      WHERE default_langcode = 1
      ORDER BY content_entity_type_id, content_entity_id;")

    MODERATION_STATES="["
    FIRST=true
    while IFS=$'\t' read -r METYPE MEID MEREV MSTATE MWORKFLOW MLANG; do
      [[ -z "$METYPE" ]] && continue
      METYPE_ESC=$(json_escape "$METYPE")
      MSTATE_ESC=$(json_escape "$MSTATE")
      MWORKFLOW_ESC=$(json_escape "$MWORKFLOW")

      [[ "$FIRST" == true ]] && FIRST=false || MODERATION_STATES="$MODERATION_STATES,"
      MODERATION_STATES="$MODERATION_STATES{\"entity_type\":\"$METYPE_ESC\",\"entity_id\":${MEID:-0},\"revision_id\":${MEREV:-0},\"state\":\"$MSTATE_ESC\",\"workflow\":\"$MWORKFLOW_ESC\",\"langcode\":\"${MLANG:-en}\"}"
    done <<< "$MOD_RAW"
    MODERATION_STATES="$MODERATION_STATES]"
  else
    echo "content_moderation_state_field_data table not found." >&2
  fi

  RESULT="{\"workflows\":$WORKFLOWS,\"moderation_states\":$MODERATION_STATES}"
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  echo "$RESULT" | json_fmt > "$OUTPUT_DIR/workflows.json"
  echo "Workflows exported to $OUTPUT_DIR/workflows.json" >&2
else
  echo "$RESULT" | json_fmt
fi
