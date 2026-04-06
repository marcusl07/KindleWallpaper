#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t79.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+QuoteEditView:[[:space:]]+View' "quote edit view definition"
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+QuoteEditSaveRequest' "quote edit save request"
require_pattern "$SETTINGS_FILE" 'TextEditor\(text:[[:space:]]*\$draft\.quoteText\)' "quote text editor"
require_pattern "$SETTINGS_FILE" 'TextField\("Book Title"' "book title field"
require_pattern "$SETTINGS_FILE" 'TextField\("Author"' "author field"
require_pattern "$SETTINGS_FILE" 'TextField\("Location"' "location field"
require_pattern "$SETTINGS_FILE" 'LabeledContent\("Linked Book"' "linked book summary"
require_pattern "$SETTINGS_FILE" 'Button\("Cancel"' "cancel action"
require_pattern "$SETTINGS_FILE" 'Button\("Save"' "save action"
require_pattern "$SETTINGS_FILE" 'QuoteEditViewTestProbe' "quote edit test probe"
require_pattern "$SETTINGS_FILE" 'Button\("Edit"\)' "quote detail edit action"
require_pattern "$APP_STATE_FILE" 'func updateQuote\(_ highlight: Highlight, with request: QuoteEditSaveRequest\)' "app-state quote update API"

cp "$ROOT_DIR/scripts/verify_t79_main.swift" "$TMP_DIR/main.swift"

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
  -o "$TMP_DIR/verify_t79_main"

"$TMP_DIR/verify_t79_main"

echo "T79 verification passed"
