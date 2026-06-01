#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t104.XXXXXX)"
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

"$ROOT_DIR/scripts/verify_t97a.sh"
"$ROOT_DIR/scripts/verify_t101.sh"
"$ROOT_DIR/scripts/verify_t102.sh"
"$ROOT_DIR/scripts/verify_t103.sh"

require_pattern "$ROOT_DIR/App/WallpaperAssignmentStore.swift" 'appGroupDefaults\.set\(true,[[:space:]]*forKey:[[:space:]]*Self\.wallpaperAssignmentsAppGroupMigrationCompletedKey\)' "App Group migration marker write"
require_pattern "$ROOT_DIR/App/AppState.swift" 'sharedDefaults\.replaceReusableGeneratedWallpapers' "main app writes wallpaper assignments through shared App Group defaults"
require_pattern "$ROOT_DIR/App/AppState.swift" 'loadReusableGeneratedWallpapersWithLegacyFallback' "main app restores wallpaper assignments through App Group defaults with legacy fallback"
require_pattern "$ROOT_DIR/App/AppState.swift" 'retryWallpaperAssignmentMigrationIfNeeded' "main app retries incomplete assignment migration after successful rotations"
require_pattern "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" 'migrateWallpaperAssignmentsToAppGroupIfNeeded' "helper launch bounded migration attempt"
require_pattern "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" 'loadReusableGeneratedWallpapersWithLegacyFallback' "helper restores wallpaper assignments with legacy fallback"
require_pattern "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" 'DisplayTopologyCoordinator' "helper display/wake observer runtime"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/scripts/verify_t104_main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/WallpaperAssignmentStore.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/WallpaperTopologyRestorer.swift" \
  -o "$TMP_DIR/verify_t104_main"

"$TMP_DIR/verify_t104_main"

echo "T104 verification passed"
