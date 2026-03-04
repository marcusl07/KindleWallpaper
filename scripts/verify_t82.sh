#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t82.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'func[[:space:]]+requestWallpaperRotation\(forcedHighlight:[[:space:]]*Highlight\?[[:space:]]*=[[:space:]]*nil\)' "forced highlight request API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+requestWallpaperRotationSynchronously\(forcedHighlight:[[:space:]]*Highlight\?[[:space:]]*=[[:space:]]*nil\)' "forced highlight synchronous request API"
require_pattern "$APP_STATE_FILE" 'makeRotationPipelineContext\(forcedHighlight:[[:space:]]*forcedHighlight\)' "forced highlight pipeline wiring"
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+QuoteDetailView:[[:space:]]+View' "quote detail view definition"
require_pattern "$SETTINGS_FILE" 'Button\("Set as Current Wallpaper"\)' "set wallpaper action button"
require_pattern "$SETTINGS_FILE" 'requestWallpaperRotation\(forcedHighlight:[[:space:]]*highlight\)' "detail view forced rotation request"
require_pattern "$SETTINGS_FILE" 'QuoteDetailView\(highlight:[[:space:]]*highlight\)' "quote row navigation to detail view"

cp "$ROOT_DIR/scripts/verify_t82_main.swift" "$TMP_DIR/main.swift"

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
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t82_main"

"$TMP_DIR/verify_t82_main"

echo "T82 verification passed"
