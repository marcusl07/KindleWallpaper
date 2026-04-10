#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t121a.XXXXXX)"
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

require_pattern "$APP_FILE" 'orderFrontRegardless\(\)' "inactive settings-window restore path"
require_pattern "$APP_FILE" 'func[[:space:]]+testRestoreWindowVisibilityAfterAppDeactivation\(\)' "testing helper for app-deactivation restore"
require_pattern "$APP_FILE" 'func[[:space:]]+testOrderOutSettingsWindow\(\)' "testing helper for ordered-out window restoration"
require_pattern "$APP_FILE" 'var[[:space:]]+testIsSettingsWindowKey:[[:space:]]+Bool' "testing helper for key-window state"
require_pattern "$APP_FILE" 'func[[:space:]]+restoreWindowVisibilityAfterAppDeactivation\(\)' "probe app-deactivation restore helper"
require_pattern "$APP_FILE" 'func[[:space:]]+orderOutSettingsWindow\(\)' "probe ordered-out window helper"
require_pattern "$APP_FILE" 'var[[:space:]]+isSettingsWindowKey:[[:space:]]+Bool' "probe key-window state"

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
  "$ROOT_DIR/Models/BulkBookDeletionPlan.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

cp "$ROOT_DIR/scripts/verify_t121a_main.swift" "$TMP_DIR/main.swift"

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
  "$ROOT_DIR/Models/BulkBookDeletionPlan.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t121a_main"

"$TMP_DIR/verify_t121a_main"

echo "T121-a verification passed"
