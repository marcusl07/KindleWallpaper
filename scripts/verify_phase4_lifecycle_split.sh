#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
APP_ENTRY_FILE="$ROOT_DIR/App/KindleWallApp.swift"
APP_DELEGATE_FILE="$ROOT_DIR/App/LeafAppDelegate.swift"
LIFECYCLE_FILE="$ROOT_DIR/App/LeafAppLifecycle.swift"
SETTINGS_COORDINATOR_FILE="$ROOT_DIR/App/SettingsWindowCoordinator.swift"
STATUS_ITEM_FILE="$ROOT_DIR/App/StatusItemController.swift"
ROTATION_SERVICE_FILE="$ROOT_DIR/App/WallpaperRotationService.swift"
LAUNCH_SERVICE_FILE="$ROOT_DIR/App/LaunchAtLoginService.swift"
DISPLAY_TOPOLOGY_FILE="$ROOT_DIR/App/DisplayTopologyCoordinator.swift"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file" >&2
    exit 1
  fi
}

forbid_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if rg -q "$pattern" "$file"; then
    echo "Verification failed: found unexpected $description in $file" >&2
    exit 1
  fi
}

require_pattern "$APP_ENTRY_FILE" 'struct[[:space:]]+KindleWallApp:[[:space:]]+App' "app entry point"
forbid_pattern "$APP_ENTRY_FILE" 'final[[:space:]]+class[[:space:]]+AppDelegate' "delegate implementation in app entry"
forbid_pattern "$APP_ENTRY_FILE" 'final[[:space:]]+class[[:space:]]+SettingsWindowCoordinator' "settings coordinator implementation in app entry"
forbid_pattern "$APP_ENTRY_FILE" 'final[[:space:]]+class[[:space:]]+StatusItemController' "status item implementation in app entry"
forbid_pattern "$APP_ENTRY_FILE" 'struct[[:space:]]+AppLaunchLifecycleController' "launch lifecycle implementation in app entry"

require_pattern "$LIFECYCLE_FILE" 'struct[[:space:]]+AppLaunchLifecycleController' "launch lifecycle controller"
require_pattern "$LIFECYCLE_FILE" 'handleAppStateConfigured' "configured-after-launch path"
require_pattern "$LIFECYCLE_FILE" 'applicationDidFinishLaunching' "app launch lifecycle path"
require_pattern "$LIFECYCLE_FILE" 'AppLaunchLifecycleTestProbe' "lifecycle test support"

require_pattern "$APP_DELEGATE_FILE" 'final[[:space:]]+class[[:space:]]+AppDelegate:[[:space:]]+NSObject,[[:space:]]+NSApplicationDelegate' "app delegate"
require_pattern "$APP_DELEGATE_FILE" 'NSApp\.setActivationPolicy\(\.accessory\)' "accessory app launch policy"
require_pattern "$APP_DELEGATE_FILE" 'StatusItemController' "status item controller ownership"
require_pattern "$APP_DELEGATE_FILE" 'SettingsWindowCoordinator' "settings window coordinator ownership"
require_pattern "$APP_DELEGATE_FILE" 'DisplayTopologyCoordinator' "display topology coordinator ownership"
require_pattern "$APP_DELEGATE_FILE" 'reapplyCurrentWallpaperForTopologyChange' "startup wallpaper restore path"
require_pattern "$APP_DELEGATE_FILE" 'requestWallpaperRotation\(\)' "menu-triggered manual rotation path"

require_pattern "$SETTINGS_COORDINATOR_FILE" 'final[[:space:]]+class[[:space:]]+SettingsWindowCoordinator:[[:space:]]+NSObject,[[:space:]]+NSWindowDelegate' "settings coordinator"
require_pattern "$SETTINGS_COORDINATOR_FILE" 'func[[:space:]]+showWindow\(\)' "library window command"
require_pattern "$SETTINGS_COORDINATOR_FILE" 'func[[:space:]]+showPreferencesWindow\(\)' "settings window command"
require_pattern "$SETTINGS_COORDINATOR_FILE" 'window\.hidesOnDeactivate[[:space:]]*=[[:space:]]*false' "background-visible settings behavior"
require_pattern "$SETTINGS_COORDINATOR_FILE" 'SettingsWindowCoordinatorTestProbe' "settings window test support"

require_pattern "$STATUS_ITEM_FILE" 'final[[:space:]]+class[[:space:]]+StatusItemController:[[:space:]]+NSObject' "status item controller"
require_pattern "$STATUS_ITEM_FILE" 'NSStatusBar\.system\.statusItem' "menu bar status item"
require_pattern "$STATUS_ITEM_FILE" 'MenuBarView' "existing menu view"
require_pattern "$STATUS_ITEM_FILE" 'nextQuoteAction:[[:space:]]*rotateWallpaper' "Next Quote menu action"
require_pattern "$STATUS_ITEM_FILE" 'openSettingsAction:[[:space:]]*openSettings' "Open Library menu action"
require_pattern "$STATUS_ITEM_FILE" 'openPreferencesAction:[[:space:]]*openPreferences' "Settings menu action"

require_pattern "$ROTATION_SERVICE_FILE" 'enum[[:space:]]+WallpaperRotationService' "wallpaper rotation service"
require_pattern "$ROTATION_SERVICE_FILE" 'static[[:space:]]+func[[:space:]]+run\(using[[:space:]]+context:[[:space:]]+Context\)' "rotation pipeline service entry"
require_pattern "$APP_STATE_FILE" 'WallpaperRotationService\.run' "AppState delegated rotation pipeline"
require_pattern "$APP_STATE_FILE" 'WallpaperRotationService\.enqueue' "AppState delegated rotation work queue"
require_pattern "$APP_STATE_FILE" 'WallpaperRotationService\.deliverOnMain' "AppState delegated rotation delivery"

require_pattern "$LAUNCH_SERVICE_FILE" 'enum[[:space:]]+LaunchAtLoginService' "launch-at-login service"
require_pattern "$LAUNCH_SERVICE_FILE" 'SMAppService\.mainApp' "main-app launch-at-login mapping"
require_pattern "$APP_STATE_FILE" 'LaunchAtLoginService\.currentEnabled' "AppState launch-at-login status service"
require_pattern "$APP_STATE_FILE" 'LaunchAtLoginService\.setEnabled' "AppState launch-at-login mutation service"

require_pattern "$DISPLAY_TOPOLOGY_FILE" 'reapplyCurrentWallpaperForTopologyChange' "running-app display restore path"

echo "Phase 4 lifecycle split verification passed"
