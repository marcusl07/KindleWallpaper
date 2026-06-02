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

require_absent() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if rg -q "$pattern" "$file"; then
    echo "Verification failed: unexpected $description in $file" >&2
    exit 1
  fi
}

require_absent "$SETTINGS_FILE" 'Picker\("Book"' "visible book filter picker"
require_absent "$SETTINGS_FILE" 'Picker\("Author"' "visible author filter picker"
require_pattern "$SETTINGS_FILE" 'Picker\("Book Status"' "book status filter picker"
require_pattern "$SETTINGS_FILE" 'Picker\("Manual Added"' "manual filter picker"
require_pattern "$SETTINGS_FILE" 'Button\("Reset Filters"' "filter reset button"
require_pattern "$SETTINGS_FILE" 'reconcileFilters\(\)' "filter reconciliation after refresh"
require_pattern "$SETTINGS_FILE" 'availableBookTitles\(from:' "book filter options helper"
require_pattern "$SETTINGS_FILE" 'availableAuthors\(from:' "author filter options helper"

cp "$ROOT_DIR/scripts/verify_t77_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t77_main"

"$TMP_DIR/verify_t77_main"

echo "T77 verification passed"
