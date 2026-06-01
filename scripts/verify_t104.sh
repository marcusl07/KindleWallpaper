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

require_pattern "$ROOT_DIR/App/WallpaperAssignmentStore.swift" 'sharedDefaultsSuiteName[[:space:]]*=[[:space:]]*"com\.marcuslo\.KindleWall"' "main app defaults domain"
require_pattern "$ROOT_DIR/App/WallpaperAssignmentStore.swift" 'UserDefaults\(suiteName:[[:space:]]*sharedDefaultsSuiteName\)' "unsigned shared defaults suite"
require_pattern "$ROOT_DIR/App/WallpaperAssignmentStore.swift" 'generatedWallpapersDirectoryURL' "local generated wallpaper directory"
require_pattern "$ROOT_DIR/App/AppState.swift" 'sharedDefaults\.replaceReusableGeneratedWallpapers' "main app writes wallpaper assignments through unsigned shared defaults"
require_pattern "$ROOT_DIR/App/AppState.swift" 'sharedDefaults\.loadReusableGeneratedWallpapers' "main app restores wallpaper assignments through unsigned shared defaults"
require_pattern "$ROOT_DIR/App/AppState.swift" 'KindleWallSharedStorage\.sharedContainerURL' "main app generates wallpapers under local Application Support"
require_pattern "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" 'KindleWallSharedStorage\.sharedUserDefaults' "helper reads standard shared defaults"
require_pattern "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" 'loadReusableGeneratedWallpapers' "helper restores wallpaper assignments"
require_pattern "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" 'DisplayTopologyCoordinator' "helper display/wake observer runtime"

if rg -q 'App Group|appGroup|wallpaperAssignmentsAppGroupMigrationCompleted|migrateWallpaperAssignmentsToAppGroupIfNeeded|loadReusableGeneratedWallpapersWithLegacyFallback' "$ROOT_DIR/App" "$ROOT_DIR/DisplayHelper"; then
  echo "Verification failed: runtime sources must not depend on App Group migration/fallback paths" >&2
  exit 1
fi

if rg -q 'CODE_SIGN_ENTITLEMENTS|entitlements|group\.com\.marcuslo\.KindleWall' "$ROOT_DIR/project.yml"; then
  echo "Verification failed: project.yml must not require App Group entitlements" >&2
  exit 1
fi

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/scripts/verify_t104_main.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/WallpaperAssignmentStore.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/WallpaperTopologyRestorer.swift" \
  -o "$TMP_DIR/verify_t104_main"

"$TMP_DIR/verify_t104_main"

echo "T104 verification passed"
