#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
MENU_FILE="$ROOT_DIR/App/MenuBarView.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"

require_pattern() {
  local pattern="$1"
  local file="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in ${file#$ROOT_DIR/}" >&2
    exit 1
  fi
}

require_pattern "final class MenuBarView" "$MENU_FILE" "MenuBarView declaration"
require_pattern "Current quote:" "$MENU_FILE" "quote preview label"
require_pattern "Next Quote" "$MENU_FILE" "Next Quote item"
require_pattern "Open Settings\\.\\.\\." "$MENU_FILE" "Open Settings item"
require_pattern "Highlights in library:" "$MENU_FILE" "library count label"
require_pattern "Quit" "$MENU_FILE" "Quit item"
require_pattern "quotePreviewCharacterLimit = 80" "$MENU_FILE" "quote truncation limit"
require_pattern "MenuBarView\\(" "$APP_FILE" "MenuBarView wiring in app shell"

TMP_DIR="$(mktemp -d /tmp/kindlewall_t29.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

echo "T29 verification passed"
