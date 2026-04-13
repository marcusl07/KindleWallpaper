#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
DEBOUNCE_FILE="$ROOT_DIR/App/DebouncedTaskScheduler.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t132a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" '@State[[:space:]]+private[[:space:]]+var[[:space:]]+searchText[[:space:]]*=' "raw quotes search state"
require_pattern "$SETTINGS_FILE" '@State[[:space:]]+private[[:space:]]+var[[:space:]]+effectiveSearchText[[:space:]]*=' "effective debounced quotes search state"
require_pattern "$SETTINGS_FILE" 'pendingSearchRefreshTask[[:space:]]*=[[:space:]]*searchRefreshDebounceScheduler\.schedule' "debounced search scheduling"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+commitState[[:space:]]*=[[:space:]]*QuotesListSearchPresentationModel\.commitSearchRefresh' "effective search commit state"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+currentSearchText[[:space:]]*=[[:space:]]*refreshQueryState\.searchText' "refresh query capture from committed search state"
require_pattern "$SETTINGS_FILE" 'QuotesListSearchPresentationModel\.pagingSearchText' "paging query capture from committed search state"
require_pattern "$DEBOUNCE_FILE" 'struct[[:space:]]+DebouncedTaskScheduler' "debounced task scheduler abstraction"

cp "$ROOT_DIR/scripts/verify_t132a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t132a_main"

"$TMP_DIR/verify_t132a_main"

echo "T132-a verification passed"
