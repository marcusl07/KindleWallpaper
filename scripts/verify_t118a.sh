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
require_pattern "$APP_STATE_FILE" 'async[[:space:]]+let[[:space:]]+loadedHighlights' "parallel snapshot highlight fetch"
require_pattern "$APP_STATE_FILE" 'async[[:space:]]+let[[:space:]]+loadedCount' "parallel snapshot count fetch"
require_pattern "$APP_STATE_FILE" 'async[[:space:]]+let[[:space:]]+loadedBookTitles' "parallel snapshot title fetch"
require_pattern "$APP_STATE_FILE" 'async[[:space:]]+let[[:space:]]+loadedAuthors' "parallel snapshot author fetch"
require_pattern "$APP_STATE_FILE" 'let[[:space:]]+quotesQueryService:[[:space:]]+QuotesQueryService' "app state service ownership"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+snapshot[[:space:]]*=[[:space:]]*await[[:space:]]+quotesQueryService\.loadSnapshot' "quotes refresh service wiring"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+nextPage[[:space:]]*=[[:space:]]*await[[:space:]]+quotesQueryService\.loadPage' "quotes pagination service wiring"

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

"$TMP_DIR/verify_t118a_main"

echo "T118-a verification passed"
