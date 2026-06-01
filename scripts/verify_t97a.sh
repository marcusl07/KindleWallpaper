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

require_pattern "$ASSIGNMENT_STORE_FILE" 'sharedDefaultsSuiteName[[:space:]]*=[[:space:]]*"com\.marcuslo\.KindleWall"' "main app defaults domain"
require_pattern "$ASSIGNMENT_STORE_FILE" 'UserDefaults\(suiteName:[[:space:]]*sharedDefaultsSuiteName\)' "unsigned shared defaults suite"
require_pattern "$ASSIGNMENT_STORE_FILE" 'sharedContainerURL' "local shared storage container"
require_pattern "$ASSIGNMENT_STORE_FILE" 'generatedWallpapersDirectoryURL' "local generated wallpaper directory"
require_pattern "$ASSIGNMENT_STORE_FILE" 'generatedWallpapersDirectoryName[[:space:]]*=[[:space:]]*"generated-wallpapers"' "shared generated wallpaper directory constant"

if rg -q 'App Group|appGroup|wallpaperAssignmentsAppGroupMigrationCompleted|migrateWallpaperAssignmentsToAppGroupIfNeeded|loadReusableGeneratedWallpapersWithLegacyFallback' "$SCHEDULE_SETTINGS_FILE" "$ASSIGNMENT_STORE_FILE"; then
  echo "Verification failed: assignment storage must not depend on App Group migration/fallback paths" >&2
  exit 1
fi

cp "$ROOT_DIR/scripts/verify_t97a_main.swift" "$TMP_DIR/main.swift"
cp "$ROOT_DIR/App/AppSupportPaths.swift" "$TMP_DIR/AppSupportPaths.swift"
cp "$ROOT_DIR/App/ScheduleSettings.swift" "$TMP_DIR/ScheduleSettings.swift"
cp "$ROOT_DIR/App/WallpaperAssignmentStore.swift" "$TMP_DIR/WallpaperAssignmentStore.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$TMP_DIR/AppSupportPaths.swift" \
  "$TMP_DIR/ScheduleSettings.swift" \
  "$TMP_DIR/WallpaperAssignmentStore.swift" \
  -o "$TMP_DIR/verify_t97a_main"

"$TMP_DIR/verify_t97a_main"

echo "T97-a verification passed"
