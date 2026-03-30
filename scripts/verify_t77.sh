#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t77.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'Picker\("Book"' "book filter picker"
require_pattern "$SETTINGS_FILE" 'Picker\("Author"' "author filter picker"
require_pattern "$SETTINGS_FILE" 'Picker\("Book Status"' "book status filter picker"
require_pattern "$SETTINGS_FILE" 'Picker\("Manual Added"' "manual filter picker"
require_pattern "$SETTINGS_FILE" 'Button\("Reset Filters"' "filter reset button"
require_pattern "$SETTINGS_FILE" 'reconcileFilters\(\)' "filter reconciliation after refresh"
require_pattern "$SETTINGS_FILE" 'availableBookTitles\(from:' "book filter options helper"
require_pattern "$SETTINGS_FILE" 'availableAuthors\(from:' "author filter options helper"

cp "$ROOT_DIR/scripts/verify_t77_main.swift" "$TMP_DIR/main.swift"

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
  -o "$TMP_DIR/verify_t77_main"

"$TMP_DIR/verify_t77_main"

echo "T77 verification passed"
