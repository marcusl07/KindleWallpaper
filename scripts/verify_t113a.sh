#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t113a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+displayedHighlights\(' "displayedHighlights helper"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+displayedHighlights[[:space:]]*=[[:space:]]*QuotesListPresentationModel\.displayedHighlights\(' "single displayedHighlights computation in body"
require_pattern "$SETTINGS_FILE" 'controlsRow\(displayedCount:[[:space:]]*displayedHighlights\.count\)' "controls row reusing computed displayed count"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+filteredHighlightIDs\(' "filtered-highlight test probe"

if sed -n '/static func displayedHighlights/,/static func sortedHighlights/p' "$SETTINGS_FILE" | rg -q 'sortMode'; then
  echo "Verification failed: displayedHighlights should not re-sort by sortMode" >&2
  exit 1
fi

if ! sed -n '/private func updateStoredHighlight/,/private func reconcileFilters/p' "$SETTINGS_FILE" | rg -q 'refreshHighlights\(\)'; then
  echo "Verification failed: updateStoredHighlight should refresh the sorted highlight list" >&2
  exit 1
fi

cp "$ROOT_DIR/scripts/verify_t113a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t113a_main"

"$TMP_DIR/verify_t113a_main"

echo "T113-a verification passed"
