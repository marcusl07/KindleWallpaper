#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t124a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'enum[[:space:]]+QuotesListPrimaryContent' "quotes primary-content presentation enum"
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+QuotesListContentPresentationState' "quotes content presentation state"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+presentationState\(' "content presentation helper"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+resolvedPrimaryContent\(' "resolved primary-content helper"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+resultCountSummary\(' "quotes result-count presentation helper"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+reconciledSelection\(' "quotes selection reconciliation helper"

bash "$ROOT_DIR/scripts/verify_t100.sh"
bash "$ROOT_DIR/scripts/verify_t117a.sh"
bash "$ROOT_DIR/scripts/verify_t118a.sh"
bash "$ROOT_DIR/scripts/verify_t122a.sh"
bash "$ROOT_DIR/scripts/verify_t123a.sh"
bash "$ROOT_DIR/scripts/verify_t125a.sh"
bash "$ROOT_DIR/scripts/verify_t126a.sh"
bash "$ROOT_DIR/scripts/verify_t127a.sh"
bash "$ROOT_DIR/scripts/verify_t128a.sh"
bash "$ROOT_DIR/scripts/verify_t130a.sh"
bash "$ROOT_DIR/scripts/verify_t131a.sh"
bash "$ROOT_DIR/scripts/verify_t132a.sh"

cp "$ROOT_DIR/scripts/verify_t124a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t124a_main"

"$TMP_DIR/verify_t124a_main"

echo "T124-a verification passed"
