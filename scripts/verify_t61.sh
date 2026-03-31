#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
WALLPAPER_SETTER_FILE="$ROOT_DIR/App/WallpaperSetter.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t61.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+ReapplyStoredWallpaper' "stored wallpaper reapply boundary"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+reapplyStoredWallpaperIfAvailable\(\)[[:space:]]*->[[:space:]]*WallpaperRestoreOutcome' "app state wake reapply API"
require_pattern "$APP_FILE" 'NSWorkspace\.didWakeNotification' "wake notification observer"
require_pattern "$APP_FILE" 'reapplyStoredWallpaperIfAvailable' "wake-triggered wallpaper reapply call"
require_pattern "$WALLPAPER_SETTER_FILE" 'func[[:space:]]+restoreStoredWallpapers' "stored wallpaper reapply entrypoint"
require_pattern "$WALLPAPER_SETTER_FILE" 'StoredGeneratedWallpaper\.allScreensTargetIdentifier' "all-screens restore handling"

cp "$ROOT_DIR/scripts/verify_t61_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t61_main"

"$TMP_DIR/verify_t61_main"

echo "T61 verification passed"
