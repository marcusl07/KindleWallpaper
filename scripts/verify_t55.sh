#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"

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
    echo "Verification failed: found unexpected $description in $file" >&2
    exit 1
  fi
}

# Main settings should be settings-only and trigger a dedicated books window intent.
require_pattern "$SETTINGS_FILE" 'Button\("Show Books\.\.\."\)' 'Show Books button'
require_pattern "$SETTINGS_FILE" 'BooksWindowPresentation\.requestShowWindow\(' 'books window presentation trigger'
forbid_pattern "$SETTINGS_FILE" 'SettingsRoute' 'route-based settings/books split'
forbid_pattern "$SETTINGS_FILE" 'showBooksAction' 'closure-based books presentation in settings view'
forbid_pattern "$SETTINGS_FILE" 'closeBooksAction' 'closure-based books dismissal in settings view'

# Books list must exist as its own view type.
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+BooksListView:[[:space:]]*View' 'BooksListView declaration'
require_pattern "$SETTINGS_FILE" 'Button\("Select All"\)' 'Select All control'
require_pattern "$SETTINGS_FILE" 'Button\("Deselect All"\)' 'Deselect All control'
require_pattern "$SETTINGS_FILE" 'ForEach\(appState\.books\)' 'books list rendering'

# Coordinator should own books window lifecycle and reuse.
require_pattern "$APP_FILE" 'private[[:space:]]+var[[:space:]]+booksWindowController:[[:space:]]+NSWindowController\?' 'books window controller state'
require_pattern "$APP_FILE" 'private[[:space:]]+var[[:space:]]+booksWindowObserver:[[:space:]]+NSObjectProtocol\?' 'books window observer state'
require_pattern "$APP_FILE" 'private[[:space:]]+func[[:space:]]+showBooksWindow\(\)' 'books window show method'
require_pattern "$APP_FILE" 'if[[:space:]]+let[[:space:]]+existingWindow[[:space:]]*=[[:space:]]*booksWindowController\?\.window' 'books window reuse guard'
require_pattern "$APP_FILE" 'let[[:space:]]+booksView[[:space:]]*=[[:space:]]*BooksListView\(\)' 'books window root view'
forbid_pattern "$APP_FILE" 'SettingsView\(.*startInBooks' 'legacy settings-in-books presentation path'

MODULE_CACHE_DIR="$(mktemp -d /tmp/kindlewall-modulecache-t55.XXXXXX)"
trap 'rm -rf "$MODULE_CACHE_DIR"' EXIT

swiftc -module-cache-path "$MODULE_CACHE_DIR" -parse "$SETTINGS_FILE"
swiftc -module-cache-path "$MODULE_CACHE_DIR" -parse "$APP_FILE"

echo "T55 verification passed"
