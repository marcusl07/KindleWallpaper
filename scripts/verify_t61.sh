#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
DISPLAY_TOPOLOGY_COORDINATOR_FILE="$ROOT_DIR/App/DisplayTopologyCoordinator.swift"
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

require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+ReapplyCurrentWallpaperForTopology' "topology-aware reapply boundary"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+reapplyCurrentWallpaperForTopologyChange\(\)[[:space:]]*->[[:space:]]*TopologyWallpaperReapplyOutcome' "structured topology reapply API"
require_pattern "$APP_FILE" 'struct[[:space:]]+AppLaunchLifecycleController' "launch lifecycle helper"
require_pattern "$APP_FILE" 'handleAppStateConfigured' "launch lifecycle configure hook"
require_pattern "$APP_FILE" 'applicationDidFinishLaunching' "launch lifecycle startup hook"
require_pattern "$APP_FILE" 'reapplyCurrentWallpaperForTopologyChange' "launch recovery uses topology-aware API"
require_pattern "$APP_FILE" 'AppLaunchLifecycleTestProbe' "launch recovery testing seam"
require_pattern "$APP_FILE" 'startDisplayTopologyCoordinator:' "display coordinator startup closure wiring"
require_pattern "$DISPLAY_TOPOLOGY_COORDINATOR_FILE" 'reapplyCurrentWallpaperForTopologyChange' "runtime topology recovery remains topology-aware"

if rg -q 'reapplyStoredWallpaperIfAvailable' "$APP_FILE"; then
  echo "Verification failed: unexpected legacy stored-wallpaper launch recovery in $APP_FILE" >&2
  exit 1
fi

cp "$ROOT_DIR/scripts/verify_t61_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$APP_STATE_FILE" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/DebouncedTaskScheduler.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$DISPLAY_TOPOLOGY_COORDINATOR_FILE" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$ROOT_DIR/App/WallpaperHistoryPruner.swift" \
  "$APP_FILE" \
  "$ROOT_DIR/Models/BulkBookDeletionPlan.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$APP_STATE_FILE" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/DebouncedTaskScheduler.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$DISPLAY_TOPOLOGY_COORDINATOR_FILE" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$ROOT_DIR/App/WallpaperHistoryPruner.swift" \
  "$APP_FILE" \
  "$ROOT_DIR/Models/BulkBookDeletionPlan.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t61_main"

"$TMP_DIR/verify_t61_main"

echo "T61 verification passed"
