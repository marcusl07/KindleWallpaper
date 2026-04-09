#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t117a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'private[[:space:]]+enum[[:space:]]+QuotesListPagingPresentationModel' "quotes paging presentation model"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+refreshResetState\(' "paging reset helper"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+shouldLoadMore\(' "load-more decision helper"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+appendPage\(' "paged append helper"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+resetState[[:space:]]*=[[:space:]]*QuotesListPagingPresentationModel\.refreshResetState' "quotes refresh reset wiring"
require_pattern "$SETTINGS_FILE" 'guard[[:space:]]+QuotesListPagingPresentationModel\.shouldLoadMore\(' "quotes load-more wiring"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+appendResult[[:space:]]*=[[:space:]]*QuotesListPagingPresentationModel\.appendPage\(' "quotes append-page wiring"
require_pattern "$SETTINGS_FILE" 'Button\("Reset Filters"\)' "quotes reset filters control"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+refreshResetState\(' "quotes paging test probe reset helper"
require_pattern "$SETTINGS_FILE" 'static[[:space:]]+func[[:space:]]+appendPage\(' "quotes paging test probe append helper"

bash "$ROOT_DIR/scripts/verify_t114a.sh"
bash "$ROOT_DIR/scripts/verify_t115a.sh"

cp "$ROOT_DIR/scripts/verify_t117a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t117a_main"

"$TMP_DIR/verify_t117a_main"

echo "T117-a verification passed"
