#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t102.XXXXXX)"
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

require_pattern "$ROOT_DIR/project.yml" 'DisplayHelper:' "DisplayHelper target"
require_pattern "$ROOT_DIR/project.yml" 'PRODUCT_BUNDLE_IDENTIFIER:[[:space:]]+com\.marcuslo\.KindleWall\.DisplayHelper' "DisplayHelper bundle identifier"
require_pattern "$ROOT_DIR/project.yml" 'Embed DisplayHelper Login Item' "main app login-item embed phase"
require_pattern "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" 'preferredSourceScreen' "preferred source screen closure in UI-less helper"
require_pattern "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" 'nil' "nil preferred source screen in UI-less helper"
require_pattern "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" 'WallpaperTopologyRestorer' "helper restorer wiring"
if rg -q 'AppState\.live|rotateWallpaper|markHighlightShown|lastChangedAt|schedule' "$ROOT_DIR/DisplayHelper"; then
  echo "Verification failed: DisplayHelper must not call main AppState or mutate rotation/schedule state" >&2
  exit 1
fi

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D DISPLAY_HELPER \
  "$ROOT_DIR/scripts/verify_t102_main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/WallpaperAssignmentStore.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/WallpaperTopologyRestorer.swift" \
  "$ROOT_DIR/App/DisplayTopologyCoordinator.swift" \
  -o "$TMP_DIR/verify_t102_main"

"$TMP_DIR/verify_t102_main"

swiftc \
  -module-cache-path "$TMP_DIR/helper-module-cache" \
  -D DISPLAY_HELPER \
  -parse-as-library \
  -typecheck \
  "$ROOT_DIR/DisplayHelper/DisplayHelperApp.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/WallpaperAssignmentStore.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/WallpaperTopologyRestorer.swift" \
  "$ROOT_DIR/App/DisplayTopologyCoordinator.swift"

echo "T102 verification passed"
