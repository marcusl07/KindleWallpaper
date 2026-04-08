#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t98.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+DeleteHighlights[[:space:]]*=[[:space:]]*\(\[UUID\]\)[[:space:]]*->[[:space:]]*Void' "bulk delete typealias"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+deleteHighlights\(ids:[[:space:]]*\[UUID\]\)' "bulk delete app state API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+deleteHighlight\(id:[[:space:]]*UUID\)' "single delete app state API"
require_pattern "$APP_STATE_FILE" 'deleteHighlights\(ids:[[:space:]]*\[id\]\)' "single delete routing through bulk path"
require_pattern "$APP_STATE_FILE" 'deleteHighlights:[[:space:]]*DatabaseManager\.deleteHighlights\(ids:\)' "live bulk delete wiring"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+deleteHighlights\(ids:[[:space:]]*\[UUID\]\)' "database bulk delete API"
require_pattern "$DATABASE_FILE" 'let[[:space:]]+capturedLiveHighlights[[:space:]]*=' "captured live highlight set"
require_pattern "$DATABASE_FILE" 'INSERT OR IGNORE INTO highlight_tombstones' "tombstone insertion during delete"
require_pattern "$DATABASE_FILE" 'DELETE FROM highlights' "highlight delete SQL"
require_pattern "$DATABASE_FILE" 'WHERE id IN' "bulk delete captured-id predicate"

cp "$ROOT_DIR/scripts/verify_t98_main.swift" "$TMP_DIR/main.swift"
cp "$ROOT_DIR/App/ScheduleSettings.swift" "$TMP_DIR/ScheduleSettings.swift"
cp "$ROOT_DIR/App/AppState.swift" "$TMP_DIR/AppState.swift"
cp "$ROOT_DIR/App/AppSupportPaths.swift" "$TMP_DIR/AppSupportPaths.swift"
cp "$ROOT_DIR/App/BackgroundImageStore.swift" "$TMP_DIR/BackgroundImageStore.swift"
cp "$ROOT_DIR/App/BackgroundImageLoader.swift" "$TMP_DIR/BackgroundImageLoader.swift"
cp "$ROOT_DIR/App/SettingsView.swift" "$TMP_DIR/SettingsView.swift"
cp "$ROOT_DIR/Models/Book.swift" "$TMP_DIR/Book.swift"
cp "$ROOT_DIR/Models/Highlight.swift" "$TMP_DIR/Highlight.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$TMP_DIR/ScheduleSettings.swift" \
  "$TMP_DIR/AppState.swift" \
  "$TMP_DIR/AppSupportPaths.swift" \
  "$TMP_DIR/BackgroundImageStore.swift" \
  "$TMP_DIR/BackgroundImageLoader.swift" \
  "$TMP_DIR/SettingsView.swift" \
  "$TMP_DIR/Book.swift" \
  "$TMP_DIR/Highlight.swift" \
  -o "$TMP_DIR/verify_t98_main"

"$TMP_DIR/verify_t98_main"

echo "T98 verification passed"
