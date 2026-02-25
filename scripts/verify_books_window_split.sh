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

# Settings view should only trigger books presentation intent.
require_pattern "$SETTINGS_FILE" 'Button\("Show Books\.\.\."\)' 'Show Books button'
require_pattern "$SETTINGS_FILE" 'BooksWindowPresentation\.requestShowWindow\(' 'books window notification trigger'
forbid_pattern "$SETTINGS_FILE" 'SettingsRoute' 'route-based settings/books navigation'
forbid_pattern "$SETTINGS_FILE" 'showBooksAction' 'closure-based books presentation hook'
forbid_pattern "$SETTINGS_FILE" 'closeBooksAction' 'closure-based books close hook'
forbid_pattern "$SETTINGS_FILE" 'startInBooks' 'settings-in-books startup mode'

# Books list is a dedicated view.
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+BooksListView:[[:space:]]*View' 'BooksListView declaration'
require_pattern "$SETTINGS_FILE" 'ForEach\(appState\.books\)' 'books list rows'
require_pattern "$SETTINGS_FILE" 'appState\.setBookEnabled\(id:[[:space:]]*book\.id,[[:space:]]*enabled:[[:space:]]*enabled\)' 'per-book toggle mutation'

# Single coordinator-owned open path.
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+let[[:space:]]+kindleWallShowBooksWindow' 'books window notification name'
require_pattern "$APP_FILE" 'private[[:space:]]+var[[:space:]]+booksWindowObserver:[[:space:]]+NSObjectProtocol\?' 'books observer storage'
require_pattern "$APP_FILE" 'addObserver\(' 'books notification observer registration'
require_pattern "$APP_FILE" '\.kindleWallShowBooksWindow' 'books notification subscription'
require_pattern "$APP_FILE" 'private[[:space:]]+func[[:space:]]+showBooksWindow\(\)' 'books window open method'
require_pattern "$APP_FILE" 'if[[:space:]]+let[[:space:]]+existingWindow[[:space:]]*=[[:space:]]*booksWindowController\?\.window' 'books window reuse guard'
require_pattern "$APP_FILE" 'let[[:space:]]+booksView[[:space:]]*=[[:space:]]*BooksListView\(\)' 'dedicated books root view'
require_pattern "$APP_FILE" 'booksWindowController\?\.[[:space:]]*window[[:space:]]*===[[:space:]]*closedWindow' 'books window teardown on close'
forbid_pattern "$APP_FILE" 'SettingsView\(.*startInBooks' 'settings view reused as books view'

# Ensure there is a single external invocation path into showBooksWindow.
SHOW_BOOKS_CALL_COUNT="$(rg -n 'showBooksWindow\(' "$APP_FILE" | wc -l | tr -d ' ')"
if [[ "$SHOW_BOOKS_CALL_COUNT" -ne 2 ]]; then
  echo "Verification failed: expected exactly 2 showBooksWindow( occurrences (definition + observer call), found $SHOW_BOOKS_CALL_COUNT" >&2
  exit 1
fi

MODULE_CACHE_DIR="$(mktemp -d /tmp/kindlewall-modulecache-books.XXXXXX)"
trap 'rm -rf "$MODULE_CACHE_DIR"' EXIT

swiftc -module-cache-path "$MODULE_CACHE_DIR" -parse "$SETTINGS_FILE"
swiftc -module-cache-path "$MODULE_CACHE_DIR" -parse "$APP_FILE"

echo "Books-window split verification passed"
