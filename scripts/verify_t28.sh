#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"

require_pattern() {
  local pattern="$1"
  local description="$2"

  if ! rg -q "$pattern" "$APP_FILE"; then
    echo "Verification failed: missing $description in App/KindleWallApp.swift" >&2
    exit 1
  fi
}

require_pattern "@main" "@main attribute"
require_pattern "struct KindleWallApp:[[:space:]]*App" "KindleWallApp declaration"
require_pattern "@StateObject[[:space:]]+private[[:space:]]+var[[:space:]]+appState:[[:space:]]+AppState" "AppState state object"
require_pattern "WallpaperScheduler\\(" "WallpaperScheduler instantiation"
require_pattern "VolumeWatcher\\.MountListener" "VolumeWatcher mount listener wiring"
require_pattern "NSStatusBar\\.system\\.statusItem" "NSStatusItem setup"
require_pattern "\\.environmentObject\\(appState\\)" "EnvironmentObject injection"
require_pattern "setActivationPolicy\\(\\.accessory\\)" "dock suppression policy"

TMP_DIR="$(mktemp -d /tmp/kindlewall_t28.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$ROOT_DIR/App/KindleWallApp.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

echo "T28 verification passed"
