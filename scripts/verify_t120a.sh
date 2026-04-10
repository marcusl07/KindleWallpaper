#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t120a.XXXXXX)"
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

require_pattern "$DATABASE_FILE" 'enum[[:space:]]+HighlightUpdateError:[[:space:]]+Error,[[:space:]]+Equatable' "recoverable highlight update error type"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+updateHighlight\(_[[:space:]]+highlight:[[:space:]]+Highlight\)[[:space:]]+throws' "throwing highlight update API"
require_pattern "$DATABASE_FILE" 'error\.extendedResultCode[[:space:]]*==[[:space:]]*\.SQLITE_CONSTRAINT_UNIQUE' "SQLite unique constraint recovery"
require_pattern "$APP_STATE_FILE" 'enum[[:space:]]+QuoteSaveError:[[:space:]]+Error,[[:space:]]+Equatable,[[:space:]]+LocalizedError' "quote save error model"
require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+UpdateHighlight[[:space:]]*=[[:space:]]*\(Highlight\)[[:space:]]+throws[[:space:]]*->[[:space:]]*Void' "throwing app-state quote update dependency"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+updateQuote\(_[[:space:]]+highlight:[[:space:]]+Highlight,[[:space:]]+with[[:space:]]+request:[[:space:]]+QuoteEditSaveRequest\)[[:space:]]+throws[[:space:]]+->[[:space:]]+Highlight' "throwing app-state quote update method"
require_pattern "$SETTINGS_FILE" '@State[[:space:]]+private[[:space:]]+var[[:space:]]+saveError:[[:space:]]+AppState\.QuoteSaveError\?' "quote edit save error state"
require_pattern "$SETTINGS_FILE" 'try[[:space:]]+onSave\(QuoteEditPresentationModel\.saveRequest' "quote edit save try path"
require_pattern "$SETTINGS_FILE" 'Button\("Dismiss"\)' "dismissible duplicate-save error UI"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+updatedHighlight[[:space:]]*=[[:space:]]*try[[:space:]]+appState\.updateQuote' "edit sheet keeps dismiss logic after successful save"
require_pattern "$SETTINGS_FILE" 'appState\.addManualQuote\(request\)' "manual quote creation path unchanged"

cp "$ROOT_DIR/scripts/verify_t120a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t120a_main"

"$TMP_DIR/verify_t120a_main"

echo "T120-a verification passed"
