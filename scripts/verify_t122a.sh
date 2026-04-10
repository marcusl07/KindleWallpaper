#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t122a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'selectedHighlightIDs:[[:space:]]+Set<UUID>' "refresh reset state selection preservation field"
require_pattern "$SETTINGS_FILE" 'preservingHighlights:' "refresh reset helper that preserves existing highlights"
require_pattern "$SETTINGS_FILE" 'selectedHighlightIDs[[:space:]]*=[[:space:]]*resetState\.selectedHighlightIDs' "refresh-start selection preservation wiring"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+reconciledSelection\(' "quotes selection reconciliation test probe"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

cp "$ROOT_DIR/scripts/verify_t122a_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t122a_main"

"$TMP_DIR/verify_t122a_main"

echo "T122-a verification passed"
