#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
PARSER_FILE="$ROOT_DIR/Parsing/ClippingsParser.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t119a.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'struct[[:space:]]+ImportStatus:[[:space:]]+Equatable' "app-state import status model"
require_pattern "$APP_STATE_FILE" '@Published[[:space:]]+private\(set\)[[:space:]]+var[[:space:]]+latestImportStatus:[[:space:]]+ImportStatus' "persisted app-state import status storage"
require_pattern "$SETTINGS_FILE" 'DisclosureGroup\("Warning details"\)' "collapsed warning details disclosure group"
require_pattern "$PARSER_FILE" 'private[[:space:]]+static[[:space:]]+func[[:space:]]+warningSnippet\(from[[:space:]]+text:[[:space:]]+String,[[:space:]]+maximumLength:[[:space:]]+Int[[:space:]]*=[[:space:]]*80\)' "80-character warning snippet cap"

bash "$ROOT_DIR/scripts/verify_t90.sh"

cp "$ROOT_DIR/scripts/verify_t119a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t119a_main"

"$TMP_DIR/verify_t119a_main"

echo "T119-a verification passed"
