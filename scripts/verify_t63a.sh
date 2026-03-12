#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
PRUNER_FILE="$ROOT_DIR/App/WallpaperHistoryPruner.swift"
SCHEDULE_FILE="$ROOT_DIR/App/ScheduleSettings.swift"
PROJECT_FILE="$ROOT_DIR/KindleWall.xcodeproj/project.pbxproj"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t63a.XXXXXX)"
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

require_pattern "$PRUNER_FILE" 'struct[[:space:]]+WallpaperHistoryPruner' "wallpaper history pruner type"
require_pattern "$PRUNER_FILE" 'PropertyListSerialization' "property list serialization usage"
require_pattern "$PRUNER_FILE" 'func[[:space:]]+staleKindleWallPNGPaths' "stale KindleWall path collector"
require_pattern "$PRUNER_FILE" 'func[[:space:]]+prune\(pathsToPrune:' "prune entrypoint"
require_pattern "$PRUNER_FILE" 'updatedChoice\.removeValue\(forKey:[[:space:]]*"Files"\)' "empty Files cleanup"
require_pattern "$APP_FILE" 'pruneStaleWallpaperHistoryIfNeeded' "startup migration helper"
require_pattern "$APP_FILE" 'defer[[:space:]]*\{' "defer-based completion"
require_pattern "$APP_FILE" 'userDefaults\.didPruneStaleWallpaperHistory[[:space:]]*=[[:space:]]*true' "completion flag write"
require_pattern "$SCHEDULE_FILE" 'didPruneStaleWallpaperHistory' "typed UserDefaults migration flag"
require_pattern "$PROJECT_FILE" 'WallpaperHistoryPruner\.swift' "project wiring for wallpaper history pruner"

cp "$ROOT_DIR/scripts/verify_t63a_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
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
  "$ROOT_DIR/App/WallpaperHistoryPruner.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t63a_main"

"$TMP_DIR/verify_t63a_main"

echo "T63a verification passed"
