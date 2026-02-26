#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t53.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'func[[:space:]]+requestWallpaperRotation\(\)[[:space:]]*->[[:space:]]*Bool' "async wallpaper rotation entrypoint"
require_pattern "$APP_STATE_FILE" 'wallpaperRotationQueue' "dedicated wallpaper rotation executor"
require_pattern "$APP_STATE_FILE" 'DispatchQueue\.main\.async' "main-thread result delivery helper"
require_pattern "$APP_FILE" 'requestWallpaperRotation\(\)' "UI and scheduler routes using async wallpaper rotation entrypoint"

cp "$ROOT_DIR/scripts/verify_t53_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t53_main"

"$TMP_DIR/verify_t53_main"

echo "T53 verification passed"
