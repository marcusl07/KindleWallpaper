#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t127a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'private[[:space:]]+enum[[:space:]]+QuotesListRefreshReason' "quotes refresh reason enum"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+currentGeneration[[:space:]]*=[[:space:]]*queryGeneration[[:space:]]*\+[[:space:]]*1' "refresh-side generation increment"
require_pattern "$SETTINGS_FILE" 'reloadsFilterOptions[[:space:]]*=[[:space:]]*QuotesListRefreshPresentationModel\.reloadsFilterOptions' "reason-based filter-options policy"
require_pattern "$SETTINGS_FILE" 'guard[[:space:]]+reloadsFilterOptions[[:space:]]+else' "sort-only page payload fast path"
require_pattern "$SETTINGS_FILE" 'shouldAcceptAsyncResult\(' "generation freshness guard"

if rg -q 'loadSnapshot\(' "$SETTINGS_FILE"; then
  echo "Verification failed: SettingsView should not couple quotes refresh to loadSnapshot" >&2
  exit 1
fi

cp "$ROOT_DIR/scripts/verify_t127a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t127a_main"

"$TMP_DIR/verify_t127a_main"

echo "T127-a verification passed"
