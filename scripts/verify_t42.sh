#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t42.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file" >&2
    exit 1
  fi
}

require_pattern "$APP_STATE_FILE" 'enum[[:space:]]+WallpaperRotationOutcome' "explicit wallpaper rotation outcome enum"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+rotateWallpaperWithOutcome\(\)[[:space:]]*->[[:space:]]*WallpaperRotationOutcome' "explicit rotation outcome boundary"
require_pattern "$APP_STATE_FILE" 'case[[:space:]]+noActivePool' "no-active-pool outcome"
require_pattern "$APP_STATE_FILE" 'case[[:space:]]+wallpaperApplyFailure' "wallpaper-apply-failure outcome"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+rotateWallpaper\(\)[[:space:]]*->[[:space:]]*Bool' "bool compatibility API"

cp "$ROOT_DIR/scripts/verify_t42_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t42_main"

"$TMP_DIR/verify_t42_main"

echo "T42 verification passed"
