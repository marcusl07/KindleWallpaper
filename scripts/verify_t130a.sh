#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t130a.XXXXXX)"
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
require_pattern "$SETTINGS_FILE" '@State[[:space:]]+private[[:space:]]+var[[:space:]]+effectiveSearchText[[:space:]]*=' "committed effective quotes search state"
require_pattern "$SETTINGS_FILE" '\.searchable\(text:[[:space:]]*\$searchText' "raw searchable binding"
require_pattern "$SETTINGS_FILE" 'QuotesListSearchPresentationModel\.commitSearchRefresh' "search commit presentation helper"
require_pattern "$SETTINGS_FILE" 'searchTextOverride:[[:space:]]*commitState\.effectiveSearchText' "search-triggered refresh using committed search text"
require_pattern "$SETTINGS_FILE" 'QuotesListSearchPresentationModel\.hasActiveQuery' "effective-search presentation state"

cp "$ROOT_DIR/scripts/verify_t130a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t130a_main"

"$TMP_DIR/verify_t130a_main"

echo "T130-a verification passed"
