#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WALLPAPER_SETTER_FILE="$ROOT_DIR/App/WallpaperSetter.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t84.XXXXXX)"
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

require_pattern "$WALLPAPER_SETTER_FILE" 'func[[:space:]]+applySharedWallpaper\(' "shared wallpaper helper entrypoint"
require_pattern "$WALLPAPER_SETTER_FILE" 'resolvedScreens:[[:space:]]*\[ResolvedScreen<' "generic resolved screen shared helper"
require_pattern "$WALLPAPER_SETTER_FILE" 'resolvedScreens\.map\(\\\.screen\)' "shared helper reuses resolved screens"
require_pattern "$WALLPAPER_SETTER_FILE" 'currentDesktopImageURL' "shared helper supports current wallpaper skip logic"

cp "$ROOT_DIR/scripts/verify_t84_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  -o "$TMP_DIR/verify_t84_main"

"$TMP_DIR/verify_t84_main"

echo "T84 verification passed"
