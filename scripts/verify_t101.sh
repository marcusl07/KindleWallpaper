#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t101.XXXXXX)"
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

require_pattern "$ROOT_DIR/App/WallpaperGenerator.swift" 'generatedWallpaperCleanupGraceInterval[^=]*=[[:space:]]*10[[:space:]]*[*][[:space:]]*60' "10 minute generated wallpaper cleanup grace interval"
require_pattern "$ROOT_DIR/App/WallpaperGenerator.swift" 'protectedGeneratedWallpapersProvider' "shared assignment cleanup protection provider"
require_pattern "$ROOT_DIR/App/AppState.swift" 'sharedDefaults\.loadReusableGeneratedWallpapers\(\)\.map\(\\.fileURL\)' "main app cleanup protection from shared persisted assignments"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/scripts/verify_t101_main.swift" \
  "$ROOT_DIR/App/WallpaperGenerator.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t101_main"

"$TMP_DIR/verify_t101_main"

echo "T101 verification passed"
