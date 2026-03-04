#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t75.XXXXXX)"
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

forbid_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if rg -q "$pattern" "$file"; then
    echo "Verification failed: unexpected $description in $file" >&2
    exit 1
  fi
}

forbid_pattern "$SETTINGS_FILE" 'Section\("Import"\)' "root import section"
require_pattern "$SETTINGS_FILE" 'Section\("Quotes"\)' "quotes section"
require_pattern "$SETTINGS_FILE" 'title:[[:space:]]*"Quotes"' "quotes navigation row title"
require_pattern "$SETTINGS_FILE" 'destination:[[:space:]]*\.quotes' "quotes navigation row destination"
require_pattern "$SETTINGS_FILE" 'case[[:space:]]+\.quotes:' "quotes navigation destination case"
require_pattern "$SETTINGS_FILE" 'QuotesListView\(\)' "quotes list view destination"
require_pattern "$SETTINGS_FILE" 'case[[:space:]]+quotes' "quotes destination enum case"
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+QuotesListView:[[:space:]]+View' "quotes list view definition"
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+QuotesImportHeaderView:[[:space:]]+View' "quotes import header view definition"
require_pattern "$SETTINGS_FILE" 'Button\("Import My Clippings\.txt\.\.\."\)' "quotes import button"

cp "$ROOT_DIR/scripts/verify_t75_main.swift" "$TMP_DIR/main.swift"

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
  -o "$TMP_DIR/verify_t75_main"

"$TMP_DIR/verify_t75_main"

echo "T75 verification passed"
