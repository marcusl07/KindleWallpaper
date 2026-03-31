#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SCHEDULE_SETTINGS_FILE="$ROOT_DIR/App/ScheduleSettings.swift"
DISPLAY_IDENTITY_RESOLVER_FILE="$ROOT_DIR/App/DisplayIdentityResolver.swift"
WALLPAPER_SETTER_FILE="$ROOT_DIR/App/WallpaperSetter.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t64.XXXXXX)"
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

require_pattern "$WALLPAPER_SETTER_FILE" 'enum[[:space:]]+RestoreOutcome' "restore outcome enum"
require_pattern "$WALLPAPER_SETTER_FILE" 'case[[:space:]]+fullRestore' "full restore outcome"
require_pattern "$WALLPAPER_SETTER_FILE" 'case[[:space:]]+partialRestore' "partial restore outcome"
require_pattern "$WALLPAPER_SETTER_FILE" 'case[[:space:]]+noStoredWallpapers' "no stored wallpapers outcome"
require_pattern "$WALLPAPER_SETTER_FILE" 'case[[:space:]]+noConnectedScreens' "no connected screens outcome"
require_pattern "$WALLPAPER_SETTER_FILE" 'case[[:space:]]+applyFailure' "apply failure outcome"
require_pattern "$WALLPAPER_SETTER_FILE" 'func[[:space:]]+restoreStoredWallpapers' "explicit restore entrypoint"
require_pattern "$DISPLAY_IDENTITY_RESOLVER_FILE" 'func[[:space:]]+resolvedAssignments' "display remapping plan builder"
require_pattern "$DISPLAY_IDENTITY_RESOLVER_FILE" 'func[[:space:]]+resolvedConnectedScreens' "connected screen resolver"
require_pattern "$SCHEDULE_SETTINGS_FILE" 'func[[:space:]]+replaceReusableGeneratedWallpapers' "replace wallpaper persistence helper"
require_pattern "$SCHEDULE_SETTINGS_FILE" 'func[[:space:]]+mergeReusableGeneratedWallpapers' "merge wallpaper persistence helper"
require_pattern "$SCHEDULE_SETTINGS_FILE" 'func[[:space:]]+clearReusableGeneratedWallpapers' "clear wallpaper persistence helper"
require_pattern "$SCHEDULE_SETTINGS_FILE" 'originX' "stored wallpaper origin metadata"
require_pattern "$SCHEDULE_SETTINGS_FILE" 'pixelWidth' "stored wallpaper size metadata"
require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+WallpaperRestoreOutcome[[:space:]]*=[[:space:]]*WallpaperSetter\.RestoreOutcome' "app state restore outcome alias"
require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+ReapplyStoredWallpaper[[:space:]]*=[[:space:]]*\(\)[[:space:]]*->[[:space:]]*WallpaperRestoreOutcome' "app state restore closure outcome"
require_pattern "$APP_STATE_FILE" 'struct[[:space:]]+StoredWallpaperAssignmentPersistence' "app state persistence operations boundary"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+replaceStoredWallpaperAssignments' "app state replace persistence API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+mergeStoredWallpaperAssignments' "app state merge persistence API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+clearStoredWallpaperAssignments' "app state clear persistence API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+reapplyStoredWallpaperIfAvailable\(\)[[:space:]]*->[[:space:]]*WallpaperRestoreOutcome' "app state structured restore API"
require_pattern "$APP_STATE_FILE" 'context\.replaceStoredWallpaperAssignments\(appliedGeneratedWallpapers\)' "post-apply replace persistence routing"
require_pattern "$APP_STATE_FILE" 'DisplayIdentityResolver\.resolvedConnectedScreens' "app state target preparation uses display resolver"
require_pattern "$APP_STATE_FILE" 'DisplayIdentityResolver\.restoreStoredWallpapers' "app state restore path uses display resolver"
if rg -q 'func[[:space:]]+reapplyStoredWallpaperIfAvailable\(\)[[:space:]]*->[[:space:]]*Bool' "$APP_STATE_FILE"; then
  echo "Verification failed: unexpected legacy Bool restore API in $APP_STATE_FILE" >&2
  exit 1
fi
if rg -q 'func[[:space:]]+storeReusableGeneratedWallpapers' "$SCHEDULE_SETTINGS_FILE"; then
  echo "Verification failed: unexpected legacy store helper in $SCHEDULE_SETTINGS_FILE" >&2
  exit 1
fi

cp "$ROOT_DIR/scripts/verify_t64_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$SCHEDULE_SETTINGS_FILE" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$DISPLAY_IDENTITY_RESOLVER_FILE" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t64_main"

"$TMP_DIR/verify_t64_main"

echo "T64 verification passed"
