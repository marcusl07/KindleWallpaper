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

require_pattern "$SETTINGS_FILE" "showBooksAction:[[:space:]]+\\(\\(\\)[[:space:]]*->[[:space:]]*Bool\\)\\?" "optional show-books action injection"
require_pattern "$SETTINGS_FILE" "closeBooksAction:[[:space:]]+\\(\\(\\)[[:space:]]*->[[:space:]]*Void\\)\\?" "optional close-books action injection"
require_pattern "$SETTINGS_FILE" "let[[:space:]]+handled[[:space:]]*=[[:space:]]*showBooksAction\\?\\(\\)[[:space:]]*\\?\\?[[:space:]]*false" "Show Books handled-state wiring"
require_pattern "$SETTINGS_FILE" "if[[:space:]]*!handled" "Show Books fallback guard"
require_pattern "$SETTINGS_FILE" "route[[:space:]]*=[[:space:]]*\\.books" "in-view books route fallback"
require_pattern "$SETTINGS_FILE" "if[[:space:]]+let[[:space:]]+closeBooksAction" "books view done/close override"
require_pattern "$SETTINGS_FILE" "Button\\(\"Done\"\\)" "books window Done button"

require_pattern "$APP_FILE" "private[[:space:]]+var[[:space:]]+booksWindowController:[[:space:]]+NSWindowController\\?" "books window controller state"
require_pattern "$APP_FILE" "private[[:space:]]+func[[:space:]]+showBooksWindow\\(\\)[[:space:]]*->[[:space:]]*Bool" "books window show method"
require_pattern "$APP_FILE" "startInBooks:[[:space:]]*true" "books window opens directly in books view"
require_pattern "$APP_FILE" "closeBooksAction:[[:space:]]*\\{[[:space:]]*\\[weak[[:space:]]+self\\]" "books window close callback wiring"
require_pattern "$APP_FILE" "showBooksAction:[[:space:]]*\\{[[:space:]]*\\[weak[[:space:]]+self\\][[:space:]]+in" "settings-to-books closure wiring"
require_pattern "$APP_FILE" "let[[:space:]]+handled[[:space:]]*=[[:space:]]*self\\.showBooksWindow\\(\\)" "settings-to-books success/failure bridge"
require_pattern "$APP_FILE" "return[[:space:]]+handled" "settings-to-books handled return"
require_pattern "$APP_FILE" "booksWindowController\\?[[:space:]]*\\.[[:space:]]*window[[:space:]]*===[[:space:]]*closedWindow" "books window close cleanup"

swiftc -frontend -parse "$SETTINGS_FILE"
swiftc -frontend -parse "$APP_FILE"

echo "H3 verification passed"
