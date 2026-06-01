#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t138a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'QuotesLibrarySearchField:[[:space:]]*NSViewRepresentable' "native search field wrapper"
require_pattern "$SETTINGS_FILE" 'searchField\.sendsSearchStringImmediately[[:space:]]*=[[:space:]]*true' "immediate native search field updates"
require_pattern "$SETTINGS_FILE" 'guard[[:space:]]+searchField\.currentEditor\(\)[[:space:]]*==[[:space:]]*nil' "no committed-state overwrite while editing"

cp "$ROOT_DIR/scripts/verify_t138a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t138a_main"

"$TMP_DIR/verify_t138a_main"

echo "T138-a verification passed"
