#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEDULE_SETTINGS_FILE="$ROOT_DIR/App/ScheduleSettings.swift"
ASSIGNMENT_STORE_FILE="$ROOT_DIR/App/WallpaperAssignmentStore.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t97a.XXXXXX)"
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

require_pattern "$SCHEDULE_SETTINGS_FILE" 'wallpaperAssignmentsAppGroupMigrationCompleted' "migration completion flag"
require_pattern "$SCHEDULE_SETTINGS_FILE" 'migrateWallpaperAssignmentsToAppGroupIfNeeded' "App Group migration entrypoint"
require_pattern "$ASSIGNMENT_STORE_FILE" 'migrateLegacyAssignments' "legacy assignment migration helper"
require_pattern "$ASSIGNMENT_STORE_FILE" 'appGroupAssignmentVerificationFailed' "App Group read-back verification"
require_pattern "$ASSIGNMENT_STORE_FILE" 'generatedWallpapersDirectoryName' "shared generated wallpaper directory constant"

cp "$ROOT_DIR/scripts/verify_t97a_main.swift" "$TMP_DIR/main.swift"
cp "$ROOT_DIR/App/ScheduleSettings.swift" "$TMP_DIR/ScheduleSettings.swift"
cp "$ROOT_DIR/App/WallpaperAssignmentStore.swift" "$TMP_DIR/WallpaperAssignmentStore.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$TMP_DIR/ScheduleSettings.swift" \
  "$TMP_DIR/WallpaperAssignmentStore.swift" \
  -o "$TMP_DIR/verify_t97a_main"

"$TMP_DIR/verify_t97a_main"

echo "T97-a verification passed"
