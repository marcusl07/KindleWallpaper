#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
DISPLAY_IDENTITY_RESOLVER_FILE="$ROOT_DIR/App/DisplayIdentityResolver.swift"
WALLPAPER_SETTER_FILE="$ROOT_DIR/App/WallpaperSetter.swift"
SCHEDULE_SETTINGS_FILE="$ROOT_DIR/App/ScheduleSettings.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t85.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'enum[[:space:]]+TopologyWallpaperReapplyOutcome' "topology reapply outcome enum"
require_pattern "$APP_STATE_FILE" 'case[[:space:]]+reapplied' "topology reapply success outcome"
require_pattern "$APP_STATE_FILE" 'case[[:space:]]+alreadyApplied' "topology reapply no-op outcome"
require_pattern "$APP_STATE_FILE" 'case[[:space:]]+noConnectedScreens' "topology reapply empty-topology outcome"
require_pattern "$APP_STATE_FILE" 'case[[:space:]]+noCurrentWallpaper' "topology reapply missing-source outcome"
require_pattern "$APP_STATE_FILE" 'case[[:space:]]+applyFailure' "topology reapply failure outcome"
require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+ReapplyCurrentWallpaperForTopology' "topology reapply closure boundary"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+reapplyCurrentWallpaperForTopologyChange\(\)[[:space:]]*->[[:space:]]*TopologyWallpaperReapplyOutcome' "app state topology reapply API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+reapplyCurrentWallpaperForTopology<Screen>' "generic topology reapply helper"
require_pattern "$APP_STATE_FILE" 'topologyWallpaperSourceScreens' "topology source screen resolution helper"
require_pattern "$APP_STATE_FILE" 'preferredSourceScreen' "preferred main-screen source parameter"
require_pattern "$APP_STATE_FILE" 'WallpaperSetter\.applySharedWallpaper' "shared wallpaper apply path"
require_pattern "$APP_STATE_FILE" 'NSWorkspace\.shared\.desktopImageURL\(for:' "live current wallpaper lookup"
require_pattern "$APP_STATE_FILE" 'preferredSourceScreen:[[:space:]]*NSScreen\.main' "live main-screen preference"
require_pattern "$DISPLAY_IDENTITY_RESOLVER_FILE" 'func[[:space:]]+resolvedConnectedScreens' "connected screen resolver dependency"
require_pattern "$WALLPAPER_SETTER_FILE" 'func[[:space:]]+applySharedWallpaper' "shared wallpaper setter helper"
require_pattern "$SCHEDULE_SETTINGS_FILE" 'struct[[:space:]]+StoredGeneratedWallpaper' "stored wallpaper model remains available"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$ROOT_DIR/scripts/verify_t85_main.swift" \
  "$APP_STATE_FILE" \
  "$SCHEDULE_SETTINGS_FILE" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$DISPLAY_IDENTITY_RESOLVER_FILE" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$WALLPAPER_SETTER_FILE" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t85_main"

"$TMP_DIR/verify_t85_main"
