#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
VOLUME_WATCHER_FILE="$ROOT_DIR/App/VolumeWatcher.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t110a.XXXXXX)"
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

bash "$ROOT_DIR/scripts/verify_t106.sh"
bash "$ROOT_DIR/scripts/verify_t107a.sh"
bash "$ROOT_DIR/scripts/verify_t108a.sh"
bash "$ROOT_DIR/scripts/verify_t109.sh"

PERSIST_IMPORT_BLOCK="$TMP_DIR/persist_import.swift"
sed -n '/static func persistImport(/,/static func fetchAllBooks()/p' "$DATABASE_FILE" > "$PERSIST_IMPORT_BLOCK"

require_pattern "$PERSIST_IMPORT_BLOCK" 'return[[:space:]]+try[[:space:]]+shared\.write[[:space:]]*\{[[:space:]]*database[[:space:]]+in' "transactional persistImport write wrapper"
require_pattern "$PERSIST_IMPORT_BLOCK" 'let[[:space:]]+existingTombstoneIdentityKeys[[:space:]]*=[[:space:]]*try[[:space:]]+fetchExistingImportTombstoneIdentityKeys' "bulk tombstone preflight inside persistImport"
require_pattern "$PERSIST_IMPORT_BLOCK" 'var[[:space:]]+knownDedupeKeys[[:space:]]*=[[:space:]]*try[[:space:]]+fetchExistingHighlightDedupeKeys' "bulk dedupe preflight inside persistImport"
require_pattern "$PERSIST_IMPORT_BLOCK" 'newHighlightCount:[[:space:]]*insertedHighlightCount' "persistImport inserted-count reporting"

require_pattern "$APP_STATE_FILE" 'func[[:space:]]+deleteHighlights\(ids:[[:space:]]*\[UUID\]\)' "bulk highlight delete entrypoint"
require_pattern "$APP_STATE_FILE" 'applyLibrarySnapshot\(deleteHighlightsAction\(ids\)\)' "snapshot-based highlight delete refresh"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+deleteBooks\(using[[:space:]]+plan:[[:space:]]*BulkBookDeletionPlan\)' "bulk book delete entrypoint"
require_pattern "$APP_STATE_FILE" 'performBookMutationUsingSnapshot[[:space:]]*\{' "snapshot-based book mutation helper usage"

require_pattern "$SETTINGS_FILE" 'enum[[:space:]]+SettingsImportFlowTestProbe' "settings import test probe"
require_pattern "$SETTINGS_FILE" 'enum[[:space:]]+ImportRefreshPresentationModel' "settings import refresh presentation model"
require_pattern "$SETTINGS_FILE" 'switch[[:space:]]+ImportRefreshPresentationModel\.refreshDecision\(for:[[:space:]]*result\.librarySnapshot\)' "settings import refresh decision switch"
require_pattern "$SETTINGS_FILE" 'appState\.applyLibrarySnapshot\(librarySnapshot\)' "settings import snapshot application"
require_pattern "$SETTINGS_FILE" 'appState\.refreshLibraryState\(\)' "settings import fallback refresh"

require_pattern "$VOLUME_WATCHER_FILE" 'if[[:space:]]+let[[:space:]]+librarySnapshot[[:space:]]*=[[:space:]]*result\.librarySnapshot' "mount listener snapshot guard"
require_pattern "$VOLUME_WATCHER_FILE" 'applyLibrarySnapshot\(librarySnapshot\)' "mount listener snapshot application"

cp "$ROOT_DIR/scripts/verify_t110a_main.swift" "$TMP_DIR/main.swift"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -parse-as-library \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}" \
  -o "$TMP_DIR/verify_t110a_main"

"$TMP_DIR/verify_t110a_main"

echo "T110-a verification passed"
