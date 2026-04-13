#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t125a.XXXXXX)"
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

require_pattern "$DATABASE_FILE" 'struct[[:space:]]+QuotesPagePayload' "quotes page payload type"
require_pattern "$DATABASE_FILE" 'struct[[:space:]]+QuotesFilterOptionsPayload' "quotes filter options payload type"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchHighlightPagePayload\(' "page payload database fetch"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchHighlightFilterOptions\(' "filter options database fetch"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+loadPagePayload\(' "page payload query service API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+loadFilterOptions\(' "filter options query service API"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+pagePayload[[:space:]]*=[[:space:]]*await[[:space:]]+quotesQueryService\.loadPagePayload' "staged page payload refresh"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+filterOptions[[:space:]]*=[[:space:]]*await[[:space:]]+quotesQueryService\.loadFilterOptions' "deferred filter options refresh"

cp "$ROOT_DIR/scripts/verify_t125a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t125a_main"

"$TMP_DIR/verify_t125a_main"

echo "T125-a verification passed"
