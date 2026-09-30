#!/usr/bin/env bash
# download-files.sh — Mirror the Drupal files directory
# Uses rsync or wget. Supports public:// and private:// schemes.
set -euo pipefail

usage() {
  cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Download/mirror Drupal managed files to a local directory.

Options:
  --source PATH      Source path or URL (e.g., /var/www/html/sites/default/files,
                     user@host:/path, or https://example.com/sites/default/files)
  --dest DIR         Local destination directory (required)
  --scheme SCHEME    File scheme to download: public, private, or all (default: public)
  --method METHOD    Download method: rsync (default for local/ssh), wget, curl
  --base-url URL     Base URL of the site (for wget/curl method)
  --dry-run          Show what would be downloaded without actually downloading
  --help             Show this help message

Examples:
  # Local copy via rsync
  $(basename "$0") --source /var/www/html/sites/default/files --dest ./files-backup

  # Remote copy via rsync over SSH
  $(basename "$0") --source user@host:/var/www/html/sites/default/files --dest ./files-backup

  # Download via wget from a live site
  $(basename "$0") --method wget --base-url https://example.com --dest ./files-backup
EOF
  exit 0
}

require_drush() {
  if ! command -v drush &>/dev/null; then
    echo "Error: drush is not installed or not in PATH." >&2
    exit 1
  fi
}

SOURCE=""
DEST=""
SCHEME="public"
METHOD=""
BASE_URL=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SOURCE="$2"; shift 2 ;;
    --dest) DEST="$2"; shift 2 ;;
    --scheme) SCHEME="$2"; shift 2 ;;
    --method) METHOD="$2"; shift 2 ;;
    --base-url) BASE_URL="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    --help) usage ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$DEST" ]]; then
  echo "Error: --dest is required." >&2
  usage
fi

# Try to auto-detect source and base URL from drush if available
if command -v drush &>/dev/null; then
  if [[ -z "$SOURCE" ]]; then
    # Get the local files path from drush
    FILES_DIR=$(drush status --field=files 2>/dev/null || true)
    DRUPAL_ROOT=$(drush status --field=root 2>/dev/null || true)
    if [[ -n "$DRUPAL_ROOT" && -n "$FILES_DIR" ]]; then
      SOURCE="$DRUPAL_ROOT/$FILES_DIR"
      echo "Auto-detected source: $SOURCE" >&2
    fi
  fi

  if [[ -z "$BASE_URL" ]]; then
    BASE_URL=$(drush status --field=uri 2>/dev/null || true)
    BASE_URL="${BASE_URL%/}"
  fi

  # Get the private files path if scheme includes private
  if [[ "$SCHEME" == "private" || "$SCHEME" == "all" ]]; then
    PRIVATE_PATH=$(drush status --field=private 2>/dev/null || true)
    if [[ -n "$PRIVATE_PATH" ]]; then
      echo "Private files path: $PRIVATE_PATH" >&2
    else
      echo "Warning: private file path not configured or not detected." >&2
    fi
  fi
fi

if [[ -z "$SOURCE" && -z "$BASE_URL" ]]; then
  echo "Error: --source or --base-url is required (or run from a Drupal root with drush)." >&2
  exit 1
fi

# Auto-detect method
if [[ -z "$METHOD" ]]; then
  if [[ "$SOURCE" == http://* || "$SOURCE" == https://* ]]; then
    METHOD="wget"
  else
    METHOD="rsync"
  fi
fi

mkdir -p "$DEST"

# ============================================================================
# Rsync method (local or SSH)
# ============================================================================
rsync_download() {
  local src="$1"
  local dst="$2"

  if ! command -v rsync &>/dev/null; then
    echo "Error: rsync is not installed." >&2
    exit 1
  fi

  # Ensure trailing slash on source for rsync to copy contents
  src="${src%/}/"

  local RSYNC_OPTS=(-avz --progress --stats)
  if [[ "$DRY_RUN" == true ]]; then
    RSYNC_OPTS+=(--dry-run)
  fi

  echo "Syncing files from $src to $dst ..." >&2
  rsync "${RSYNC_OPTS[@]}" "$src" "$dst"
}

# ============================================================================
# Wget method (HTTP/HTTPS)
# ============================================================================
wget_download() {
  local base="$1"
  local dst="$2"

  if ! command -v wget &>/dev/null; then
    echo "Error: wget is not installed. Try --method curl." >&2
    exit 1
  fi

  # Use the media manifest if available to download specific files
  # Otherwise mirror the entire files directory
  local WGET_OPTS=(--recursive --no-parent --no-host-directories --cut-dirs=2
                   --directory-prefix="$dst" --reject "index.html*"
                   --timestamping --timeout=30 --tries=3)

  if [[ "$DRY_RUN" == true ]]; then
    WGET_OPTS+=(--spider)
  fi

  local FILES_URL
  if [[ -n "$SOURCE" ]]; then
    FILES_URL="$SOURCE"
  else
    # Detect files path
    local FILES_PATH
    FILES_PATH=$(drush status --field=files 2>/dev/null || echo "sites/default/files")
    FILES_URL="$base/$FILES_PATH/"
  fi

  echo "Downloading files from $FILES_URL to $dst ..." >&2
  wget "${WGET_OPTS[@]}" "$FILES_URL" || {
    echo "wget mirror completed with some errors (this is normal for dynamic URLs)." >&2
  }
}

# ============================================================================
# Curl method (using manifest)
# ============================================================================
curl_download() {
  local base="$1"
  local dst="$2"

  if ! command -v curl &>/dev/null; then
    echo "Error: curl is not installed." >&2
    exit 1
  fi

  # If we have drush, build a file list from the database
  if command -v drush &>/dev/null; then
    echo "Building file list from database..." >&2

    local SCHEME_FILTER=""
    case "$SCHEME" in
      public) SCHEME_FILTER="AND uri LIKE 'public://%'" ;;
      private) SCHEME_FILTER="AND uri LIKE 'private://%'" ;;
      all) SCHEME_FILTER="" ;;
    esac

    local FILES_RAW
    FILES_RAW=$(drush sql:query "SELECT uri FROM file_managed WHERE status = 1 $SCHEME_FILTER ORDER BY uri;" 2>/dev/null || true)

    local FILES_PATH
    FILES_PATH=$(drush status --field=files 2>/dev/null || echo "sites/default/files")

    local COUNT=0
    local TOTAL
    TOTAL=$(echo "$FILES_RAW" | grep -c . || echo "0")
    echo "Found $TOTAL files to download." >&2

    while IFS= read -r URI; do
      [[ -z "$URI" ]] && continue
      URI=$(echo "$URI" | tr -d '[:space:]')

      local REL_PATH=""
      local DL_URL=""

      if [[ "$URI" == public://* ]]; then
        REL_PATH="${URI#public://}"
        DL_URL="$base/$FILES_PATH/$REL_PATH"
      elif [[ "$URI" == private://* ]]; then
        REL_PATH="${URI#private://}"
        DL_URL="$base/system/files/$REL_PATH"
      else
        continue
      fi

      local TARGET_FILE="$dst/$REL_PATH"
      local TARGET_DIR
      TARGET_DIR=$(dirname "$TARGET_FILE")

      COUNT=$((COUNT + 1))

      if [[ "$DRY_RUN" == true ]]; then
        echo "[DRY RUN] Would download: $DL_URL -> $TARGET_FILE" >&2
        continue
      fi

      mkdir -p "$TARGET_DIR"

      # Skip if file already exists and is non-empty
      if [[ -s "$TARGET_FILE" ]]; then
        echo "[$COUNT/$TOTAL] Skipped (exists): $REL_PATH" >&2
        continue
      fi

      curl -sS -L --create-dirs -o "$TARGET_FILE" "$DL_URL" && \
        echo "[$COUNT/$TOTAL] Downloaded: $REL_PATH" >&2 || \
        echo "[$COUNT/$TOTAL] FAILED: $REL_PATH" >&2
    done <<< "$FILES_RAW"

    echo "Download complete. $COUNT files processed." >&2
  else
    echo "Error: curl method requires drush for file list, or use --method wget." >&2
    exit 1
  fi
}

# ============================================================================
# Execute
# ============================================================================

case "$METHOD" in
  rsync)
    if [[ "$SCHEME" == "public" || "$SCHEME" == "all" ]]; then
      rsync_download "$SOURCE" "$DEST/public"
    fi
    if [[ "$SCHEME" == "private" || "$SCHEME" == "all" ]]; then
      PRIVATE_PATH=$(drush status --field=private 2>/dev/null || true)
      if [[ -n "$PRIVATE_PATH" ]]; then
        rsync_download "$PRIVATE_PATH" "$DEST/private"
      else
        echo "Warning: private file path not available, skipping." >&2
      fi
    fi
    ;;
  wget)
    wget_download "${BASE_URL:-$SOURCE}" "$DEST"
    ;;
  curl)
    curl_download "${BASE_URL}" "$DEST"
    ;;
  *)
    echo "Unknown method: $METHOD. Use rsync, wget, or curl." >&2
    exit 1
    ;;
esac

echo "Files download complete. Output directory: $DEST" >&2
