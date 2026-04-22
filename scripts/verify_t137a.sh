#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t137a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'QuotesFilterOverflowPresentationModel' "filter overflow presentation helper"
require_pattern "$SETTINGS_FILE" 'filterControlsViewportWidth' "filter viewport width state"
require_pattern "$SETTINGS_FILE" 'filterControlsContentOffset' "filter content offset state"
require_pattern "$SETTINGS_FILE" 'overflowAffordanceOverlay\(' "overflow affordance overlay wiring"
require_pattern "$SETTINGS_FILE" 'filterOverflowPresentationState\(' "overflow presentation test probe"

cp "$ROOT_DIR/scripts/verify_t137a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t137a_main"

"$TMP_DIR/verify_t137a_main"

echo "T137-a verification passed"
