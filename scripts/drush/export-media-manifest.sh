#!/usr/bin/env bash
# export-media-manifest.sh — Build a manifest of all media entities + files with download URLs
# Does NOT download files. Outputs JSON manifest.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Build a manifest of all media entities and associated files with download URLs.
Does NOT download any files — use download-files.sh for that.

Options:
  --output-dir DIR   Write manifest JSON to DIR instead of stdout
  --base-url URL     Base URL of the Drupal site (auto-detected if not set)
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
BASE_URL=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    --help) usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

require_drush

MAJOR=$(detect_major)

# Auto-detect base URL if not provided
if [[ -z "$BASE_URL" ]]; then
  BASE_URL=$(drush status --field=uri 2>/dev/null || echo "http://localhost")
  BASE_URL="${BASE_URL%/}" # strip trailing slash
fi

# Get the public files path for URL construction
FILES_PATH=$(drush status --field=files 2>/dev/null || echo "sites/default/files")
FILES_PATH="${FILES_PATH%/}"

RESULT="{"
RESULT="$RESULT\"base_url\":\"$BASE_URL\","
RESULT="$RESULT\"files_path\":\"$FILES_PATH\","
RESULT="$RESULT\"generated\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","

if [[ "$MAJOR" == "7" ]]; then
  # D7: no media module by default — export file_managed table directly
  echo "Drupal 7 detected — exporting file_managed entries." >&2

  FILES_RAW=$(sql "
    SELECT fid, uid, filename, uri, filemime, filesize, status, timestamp
    FROM file_managed
    ORDER BY fid;")

  ITEMS="["
  FIRST=true
  COUNT=0

  while IFS=$'\t' read -r FID FUID FNAME FURI FMIME FSIZE FSTATUS FTIMESTAMP; do
    [[ -z "$FID" ]] && continue

    FNAME_ESC=$(json_escape "$FNAME")
    FURI_ESC=$(json_escape "$FURI")
    FMIME_ESC=$(json_escape "$FMIME")

    # Convert uri scheme to URL: public://path -> base_url/files_path/path
    DOWNLOAD_URL=""
    if [[ "$FURI" == public://* ]]; then
      REL_PATH="${FURI#public://}"
      DOWNLOAD_URL="$BASE_URL/$FILES_PATH/$REL_PATH"
    elif [[ "$FURI" == private://* ]]; then
      REL_PATH="${FURI#private://}"
      DOWNLOAD_URL="$BASE_URL/system/files/$REL_PATH"
    else
      DOWNLOAD_URL="$FURI"
    fi
    DL_ESC=$(json_escape "$DOWNLOAD_URL")

    [[ "$FIRST" == true ]] && FIRST=false || ITEMS="$ITEMS,"
    ITEMS="$ITEMS{\"fid\":$FID,\"filename\":\"$FNAME_ESC\",\"uri\":\"$FURI_ESC\",\"mime\":\"$FMIME_ESC\",\"size\":${FSIZE:-0},\"download_url\":\"$DL_ESC\",\"timestamp\":${FTIMESTAMP:-0}}"
    COUNT=$((COUNT + 1))
  done <<< "$FILES_RAW"

  ITEMS="$ITEMS]"
  RESULT="$RESULT\"total_files\":$COUNT,\"media_entities\":[],\"files\":$ITEMS}"

else
  # D9+: media_field_data for media entities, file_managed for files

  # Media entities with their source file references
  MEDIA_RAW=$(sql "
    SELECT m.mid, m.vid, m.bundle, m.name, m.uid, m.created, m.changed, m.status
    FROM media_field_data m
    WHERE m.default_langcode = 1
    ORDER BY m.mid;" 2>/dev/null || true)

  MEDIA_ITEMS="["
  FIRST_M=true
  MEDIA_COUNT=0

  while IFS=$'\t' read -r MID MVID MBUNDLE MNAME MUID MCREATED MCHANGED MSTATUS; do
    [[ -z "$MID" ]] && continue

    MNAME_ESC=$(json_escape "$MNAME")

    # Try to find the file reference for this media entity
    # Media types store file references in different field tables depending on the bundle
    # Common patterns: media__field_media_image, media__field_media_file, etc.
    FILE_INFO=""
    for FIELD_TABLE in "media__field_media_image" "media__field_media_file" "media__field_media_document" "media__field_media_video_file" "media__field_media_audio_file"; do
      FIDS=$(sql "SELECT ${FIELD_TABLE##*__}_target_id FROM $FIELD_TABLE WHERE entity_id = $MID LIMIT 1;" 2>/dev/null || true)
      if [[ -n "$FIDS" ]]; then
        FIDS=$(echo "$FIDS" | tr -d '[:space:]')
        FI=$(sql "SELECT fid, filename, uri, filemime, filesize FROM file_managed WHERE fid = $FIDS LIMIT 1;" 2>/dev/null || true)
        if [[ -n "$FI" ]]; then
          F_FID=$(echo "$FI" | cut -f1)
          F_NAME=$(echo "$FI" | cut -f2)
          F_URI=$(echo "$FI" | cut -f3)
          F_MIME=$(echo "$FI" | cut -f4)
          F_SIZE=$(echo "$FI" | cut -f5)

          F_NAME_ESC=$(json_escape "$F_NAME")
          F_URI_ESC=$(json_escape "$F_URI")
          F_MIME_ESC=$(json_escape "$F_MIME")

          DL_URL=""
          if [[ "$F_URI" == public://* ]]; then
            REL="${F_URI#public://}"
            DL_URL="$BASE_URL/$FILES_PATH/$REL"
          elif [[ "$F_URI" == private://* ]]; then
            REL="${F_URI#private://}"
            DL_URL="$BASE_URL/system/files/$REL"
          else
            DL_URL="$F_URI"
          fi
          DL_ESC=$(json_escape "$DL_URL")

          FILE_INFO=",\"file\":{\"fid\":$F_FID,\"filename\":\"$F_NAME_ESC\",\"uri\":\"$F_URI_ESC\",\"mime\":\"$F_MIME_ESC\",\"size\":${F_SIZE:-0},\"download_url\":\"$DL_ESC\"}"
          break
        fi
      fi
    done

    [[ "$FIRST_M" == true ]] && FIRST_M=false || MEDIA_ITEMS="$MEDIA_ITEMS,"
    MEDIA_ITEMS="$MEDIA_ITEMS{\"mid\":$MID,\"bundle\":\"$MBUNDLE\",\"name\":\"$MNAME_ESC\",\"status\":${MSTATUS:-1},\"created\":${MCREATED:-0},\"changed\":${MCHANGED:-0}$FILE_INFO}"
    MEDIA_COUNT=$((MEDIA_COUNT + 1))
  done <<< "$MEDIA_RAW"

  MEDIA_ITEMS="$MEDIA_ITEMS]"

  # Also get all files from file_managed for completeness
  FILE_COUNT=$(sql "SELECT COUNT(*) FROM file_managed;" | tail -1 || echo "0")
  FILE_COUNT="${FILE_COUNT:-0}"

  RESULT="$RESULT\"total_media\":$MEDIA_COUNT,\"total_files\":$FILE_COUNT,\"media_entities\":$MEDIA_ITEMS}"
fi

if [[ -n "$OUTPUT_DIR" ]]; then
  mkdir -p "$OUTPUT_DIR"
  echo "$RESULT" | json_fmt > "$OUTPUT_DIR/media-manifest.json"
  echo "Media manifest written to $OUTPUT_DIR/media-manifest.json ($MEDIA_COUNT media entities)" >&2
else
  echo "$RESULT" | json_fmt
fi
