#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"

require_pattern() {
  local pattern="$1"
  local description="$2"

  if ! rg -q "$pattern" "$APP_FILE"; then
    echo "Verification failed: missing $description in App/KindleWallApp.swift" >&2
    exit 1
  fi
}

require_settings_pattern() {
  local pattern="$1"
  local description="$2"

  if ! rg -q "$pattern" "$SETTINGS_FILE"; then
    echo "Verification failed: missing $description in App/SettingsView.swift" >&2
    exit 1
  fi
}

forbid_pattern() {
  local pattern="$1"
  local description="$2"

  if rg -q "$pattern" "$APP_FILE"; then
    echo "Verification failed: found unexpected $description in App/KindleWallApp.swift" >&2
    exit 1
  fi
}

# T40/T48 boundary expectations: dedicated coordinator owns lifecycle.
require_pattern "private[[:space:]]+var[[:space:]]+settingsWindowCoordinator:[[:space:]]+SettingsWindowCoordinator\\?" "SettingsWindowCoordinator storage in AppDelegate"
require_pattern "private[[:space:]]+final[[:space:]]+class[[:space:]]+SettingsWindowCoordinator:[[:space:]]+NSObject,[[:space:]]+NSWindowDelegate" "SettingsWindowCoordinator type declaration"
require_pattern "settingsWindowCoordinator\\?\\.showWindow\\(\\)" "menu action routed through coordinator"

# T48 lifecycle expectations: create/reuse/teardown in one boundary.
require_pattern "func[[:space:]]+showWindow\\(\\)" "showWindow entry point"
require_pattern "if[[:space:]]+let[[:space:]]+existingWindow[[:space:]]*=[[:space:]]*settingsWindowController\\?\\.window" "existing-window reuse check"
require_pattern "existingWindow\\.makeKeyAndOrderFront\\(nil\\)" "reuse path foregrounding"
require_pattern "func[[:space:]]+windowWillClose\\(_[[:space:]]+notification:[[:space:]]+Notification\\)" "window close delegate"
require_pattern "settingsWindowController[[:space:]]*=[[:space:]]*nil" "teardown clears retained controller"

# T41 persistence expectations across deactivation.
require_pattern "window\\.canHide[[:space:]]*=[[:space:]]*false" "window canHide disabled"
require_pattern "window\\.hidesOnDeactivate[[:space:]]*=[[:space:]]*false" "window hidesOnDeactivate disabled"
require_pattern "window\\.delegate[[:space:]]*=[[:space:]]*self" "coordinator owns window delegate"
require_pattern "window\\.toolbarStyle[[:space:]]*=[[:space:]]*\\.unified" "unified toolbar style"
forbid_pattern "fullSizeContentView" "full-size content view titlebar layout"
forbid_pattern "titlebarAppearsTransparent[[:space:]]*=[[:space:]]*true" "transparent titlebar layout"

# Settings navigation should be owned by SwiftUI so destination toolbars can coexist.
require_settings_pattern "ToolbarItemGroup\\(placement:[[:space:]]*\\.navigation\\)" "SwiftUI navigation toolbar group"
require_settings_pattern "navigationModel\\.goBack\\(\\)" "SwiftUI back button action"
require_settings_pattern "navigationModel\\.goForward\\(\\)" "SwiftUI forward button action"
require_settings_pattern "disabled\\(!navigationModel\\.canGoBack\\)" "back button disabled state"
require_settings_pattern "disabled\\(!navigationModel\\.canGoForward\\)" "forward button disabled state"

# Ensure legacy ad-hoc open path is not reintroduced.
forbid_pattern "func[[:space:]]+openSettingsWindow\\(\\)" "legacy openSettingsWindow method"
forbid_pattern "NSToolbarDelegate" "custom settings toolbar delegate"
forbid_pattern "settingsBackNavigation" "legacy AppKit back toolbar item identifier"
forbid_pattern "settingsForwardNavigation" "legacy AppKit forward toolbar item identifier"

TMP_DIR="$(mktemp -d /tmp/kindlewall_t48.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/DisplayTopologyCoordinator.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$ROOT_DIR/App/WallpaperHistoryPruner.swift" \
  "$ROOT_DIR/App/KindleWallApp.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

cp "$ROOT_DIR/scripts/verify_t48_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/DisplayTopologyCoordinator.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$ROOT_DIR/App/WallpaperHistoryPruner.swift" \
  "$ROOT_DIR/App/KindleWallApp.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t48_main"

"$TMP_DIR/verify_t48_main"

echo "T48 verification passed"
