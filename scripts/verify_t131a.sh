#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t131a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+RefreshQueryState' "refresh query capture state"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+refreshQueryState\(' "refresh query capture helper"
require_pattern "$SETTINGS_FILE" 'shouldCancelPendingSearchRefresh:[[:space:]]*reason[[:space:]]*==[[:space:]]*\.searchChanged' "search-only debounce cancellation rule"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+currentSearchText[[:space:]]*=[[:space:]]*refreshQueryState\.searchText' "refresh path using committed search capture"
require_pattern "$SETTINGS_FILE" 'QuotesListSearchPresentationModel\.pagingSearchText' "paging path using committed search capture"

cp "$ROOT_DIR/scripts/verify_t131a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t131a_main"

"$TMP_DIR/verify_t131a_main"

echo "T131-a verification passed"
