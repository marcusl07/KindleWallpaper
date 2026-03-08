#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SCHEDULE_SETTINGS_FILE="$ROOT_DIR/App/ScheduleSettings.swift"
WALLPAPER_GENERATOR_FILE="$ROOT_DIR/App/WallpaperGenerator.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t62.XXXXXX)"
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

require_pattern "$SCHEDULE_SETTINGS_FILE" 'struct[[:space:]]+StoredGeneratedWallpaper' "stored generated wallpaper value type"
require_pattern "$SCHEDULE_SETTINGS_FILE" 'func[[:space:]]+storeReusableGeneratedWallpapers' "generated wallpaper persistence writer"
require_pattern "$SCHEDULE_SETTINGS_FILE" 'func[[:space:]]+loadReusableGeneratedWallpapers' "generated wallpaper persistence loader"
require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+StoreReusableGeneratedWallpapers' "reusable wallpaper persistence boundary"
require_pattern "$APP_STATE_FILE" 'context\.storeReusableGeneratedWallpapers\(appliedGeneratedWallpapers\)' "post-apply reusable wallpaper persistence"
require_pattern "$WALLPAPER_GENERATOR_FILE" 'protectedGeneratedWallpapersProvider' "protected wallpaper provider dependency"
require_pattern "$WALLPAPER_GENERATOR_FILE" 'cleanupGeneratedWallpapers\(' "cleanup helper invocation"
require_pattern "$WALLPAPER_GENERATOR_FILE" 'protecting:[[:space:]]*generatedWallpapers\.map\(\\\.fileURL\)[[:space:]]*\+[[:space:]]*protectedGeneratedWallpapersProvider\(\)' "protected cleanup argument"

cp "$ROOT_DIR/scripts/verify_t62_main.swift" "$TMP_DIR/main.swift"
cat > "$TMP_DIR/QuoteEditSaveRequest.swift" <<'SWIFT'
import Foundation

struct QuoteEditSaveRequest {
    let bookId: UUID?
    let quoteText: String
    let bookTitle: String
    let author: String
    let location: String?
}
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$TMP_DIR/QuoteEditSaveRequest.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/WallpaperGenerator.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t62_main"

"$TMP_DIR/verify_t62_main"

echo "T62 verification passed"
