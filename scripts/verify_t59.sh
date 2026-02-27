#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SCHEDULE_FILE="$ROOT_DIR/App/ScheduleSettings.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t59.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'Toggle\("Capitalize first letter of highlight text"' "settings capitalize toggle"
require_pattern "$APP_STATE_FILE" '@Published[[:space:]]+private\(set\)[[:space:]]+var[[:space:]]+capitalizeHighlightText' "app state toggle state"
require_pattern "$APP_STATE_FILE" 'setCapitalizeHighlightText\(_[[:space:]]+enabled:[[:space:]]+Bool\)' "app state toggle mutation API"
require_pattern "$APP_STATE_FILE" 'transformQuoteTextForDisplay' "rotation quote transformation boundary"
require_pattern "$SCHEDULE_FILE" 'static[[:space:]]+let[[:space:]]+capitalizeHighlightText[[:space:]]*=' "user defaults toggle key"
require_pattern "$SCHEDULE_FILE" 'var[[:space:]]+capitalizeHighlightText:[[:space:]]+Bool' "user defaults toggle property"

cp "$ROOT_DIR/scripts/verify_t59_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/verify_t59_main"

"$TMP_DIR/verify_t59_main"

echo "T59 verification passed"
