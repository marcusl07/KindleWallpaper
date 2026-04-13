#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t118a.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'struct[[:space:]]+QuotesQuerySnapshot' "quotes query snapshot type"
require_pattern "$APP_STATE_FILE" 'final[[:space:]]+class[[:space:]]+QuotesQueryService' "quotes query service type"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+loadPagePayload\(' "page payload query service API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+loadFilterOptions\(' "filter options query service API"
require_pattern "$APP_STATE_FILE" 'async[[:space:]]+let[[:space:]]+pagePayload' "parallel snapshot page payload fetch"
require_pattern "$APP_STATE_FILE" 'async[[:space:]]+let[[:space:]]+filterOptions' "parallel snapshot filter-options fetch"
require_pattern "$APP_STATE_FILE" 'let[[:space:]]+quotesQueryService:[[:space:]]+QuotesQueryService' "app state service ownership"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+pagePayload[[:space:]]*=[[:space:]]*await[[:space:]]+quotesQueryService\.loadPagePayload' "quotes staged refresh page wiring"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+filterOptions[[:space:]]*=[[:space:]]*await[[:space:]]+quotesQueryService\.loadFilterOptions' "quotes staged refresh filter wiring"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+nextPage[[:space:]]*=[[:space:]]*await[[:space:]]+quotesQueryService\.loadPage' "quotes pagination service wiring"
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+QuotesListRowModel' "quotes row presentation model"
require_pattern "$SETTINGS_FILE" 'struct[[:space:]]+QuotesListRowView:[[:space:]]+View,[[:space:]]+Equatable' "equatable quotes row view"
require_pattern "$SETTINGS_FILE" 'split\(whereSeparator:[[:space:]]+\{[[:space:]]+\$0\.isWhitespace[[:space:]]+\}\)\.joined\(separator:[[:space:]]+" "\)' "non-regex preview whitespace collapse"

cp "$ROOT_DIR/scripts/verify_t118a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t118a_main"

KINDLEWALL_ROOT_DIR="$ROOT_DIR" "$TMP_DIR/verify_t118a_main"

echo "T118-a verification passed"
