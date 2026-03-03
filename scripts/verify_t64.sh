#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t64.XXXXXX)"
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

require_absent() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if rg -q "$pattern" "$file"; then
    echo "Verification failed: unexpected $description in $file" >&2
    exit 1
  fi
}

require_pattern "$SETTINGS_FILE" 'NavigationLink\("Show Books\.\.\."\)' "books navigation link"
require_pattern "$SETTINGS_FILE" 'BooksListView\(\)' "books destination view"
require_pattern "$SETTINGS_FILE" '\.navigationTitle\("Books"\)' "books destination navigation title"
require_absent "$SETTINGS_FILE" 'Button\("Show Books\.\.\."\)' "books window button"
require_absent "$SETTINGS_FILE" 'presentBooksWindowDirectly\(' "direct books window presenter"
require_absent "$SETTINGS_FILE" 'enum[[:space:]]+BooksWindowPresentation' "books window notification presenter"
require_absent "$SETTINGS_FILE" 'DirectBooksWindowStore' "direct books window storage"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

echo "T64 verification passed"
