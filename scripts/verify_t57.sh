#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
STORE_FILE="$ROOT_DIR/App/BackgroundImageStore.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t57.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'Button\("Show Backgrounds\.\.\."\)' "Show Backgrounds entry point"
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+BackgroundsListView:[[:space:]]*View' "BackgroundsListView declaration"
require_pattern "$SETTINGS_FILE" 'LazyVGrid' "background preview grid"
require_pattern "$SETTINGS_FILE" 'setPrimaryBackgroundImageSelection\(id:[[:space:]]*id\)' "clickable background selection action"
require_pattern "$SETTINGS_FILE" 'Button\("Remove Selected"\)' "remove action"
require_pattern "$SETTINGS_FILE" 'kindleWallShowBackgroundsWindow' "backgrounds window notification"

require_pattern "$APP_FILE" 'backgroundsWindowController:[[:space:]]+NSWindowController\?' "backgrounds window retention"
require_pattern "$APP_FILE" 'installBackgroundsWindowObserver' "backgrounds observer setup"
require_pattern "$APP_FILE" 'private[[:space:]]+func[[:space:]]+showBackgroundsWindow\(\)' "backgrounds open flow"
require_pattern "$APP_FILE" 'private[[:space:]]+func[[:space:]]+configureBackgroundsWindow\(_[[:space:]]+window:[[:space:]]+NSWindow\)' "backgrounds window configuration"
require_pattern "$APP_FILE" 'backgroundsWindowController\?\.[[:space:]]*window[[:space:]]*===[[:space:]]*closedWindow' "backgrounds teardown on close"

require_pattern "$APP_STATE_FILE" 'struct[[:space:]]+BackgroundCollectionState' "app state background collection boundary model"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+loadBackgroundCollectionState\(\)[[:space:]]*->[[:space:]]*BackgroundCollectionState' "collection state loader"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+setPrimaryBackgroundImageSelection\(id:[[:space:]]*UUID\)[[:space:]]*throws' "primary image mutation boundary"

require_pattern "$STORE_FILE" 'func[[:space:]]+promoteBackgroundImage\(id:[[:space:]]*UUID\)' "store promotion API"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$ROOT_DIR/App/KindleWallApp.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

cp "$ROOT_DIR/scripts/verify_t57_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t57_main"

"$TMP_DIR/verify_t57_main"

echo "T57 verification passed"
