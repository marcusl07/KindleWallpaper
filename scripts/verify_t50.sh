#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
WALLPAPER_GENERATOR_FILE="$ROOT_DIR/App/WallpaperGenerator.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t50.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'func[[:space:]]+requestWallpaperRotation\(\)[[:space:]]*->[[:space:]]*Bool' "requestWallpaperRotation entrypoint"
require_pattern "$APP_STATE_FILE" 'guard[[:space:]]+!isRotationInProgress[[:space:]]+else' "request in-progress guard"
require_pattern "$APP_STATE_FILE" 'self\.isRotationInProgress[[:space:]]*=[[:space:]]*false' "in-progress reset on publish"
require_pattern "$WALLPAPER_GENERATOR_FILE" 'func[[:space:]]+outputFilename\(rotationID:[[:space:]]*String,[[:space:]]*targetIdentifier:[[:space:]]*String\)[[:space:]]*->[[:space:]]*String' "output filename helper"
require_pattern "$WALLPAPER_GENERATOR_FILE" 'sanitizedRotationID.*sanitizedTargetIdentifier' "rotation-id + target-id output identity"

cp "$ROOT_DIR/scripts/verify_t50_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/WallpaperGenerator.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t50_main"

"$TMP_DIR/verify_t50_main"

echo "T50 verification passed"
