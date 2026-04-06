#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APPSTATE_FILE="$ROOT_DIR/App/AppState.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t83.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" '\.sheet\(isPresented:[[:space:]]*\$isPresentingAddQuote\)' "add quote sheet wiring"
require_pattern "$SETTINGS_FILE" 'Image\(systemName:[[:space:]]*"plus"\)' "plus button"
require_pattern "$SETTINGS_FILE" 'QuoteEditView\(' "quote edit presentation"
require_pattern "$SETTINGS_FILE" 'appState\.addManualQuote\(request\)' "manual quote save action"
require_pattern "$APPSTATE_FILE" 'func[[:space:]]+addManualQuote\(_ request:[[:space:]]*QuoteEditSaveRequest\)' "app state manual quote API"
require_pattern "$APPSTATE_FILE" 'insertHighlight:[[:space:]]*DatabaseManager\.insertHighlightIfNew' "live insert highlight wiring"

cp "$ROOT_DIR/scripts/verify_t83_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t83_main"

"$TMP_DIR/verify_t83_main"

echo "T83 verification passed"
