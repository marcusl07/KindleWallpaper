#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t99.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+PrepareBulkBookDeletion[[:space:]]*=[[:space:]]*\(\[UUID\]\)[[:space:]]*->[[:space:]]*BulkBookDeletionPlan' "bulk book deletion plan typealias"
require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+DeleteBooks[[:space:]]*=[[:space:]]*\(BulkBookDeletionPlan\)[[:space:]]*->[[:space:]]*LibrarySnapshot' "bulk book delete snapshot typealias"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+prepareBulkBookDeletion\(bookIDs:[[:space:]]*\[UUID\]\)' "bulk book deletion plan app state API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+deleteBooks\(using[[:space:]]+plan:[[:space:]]*BulkBookDeletionPlan\)' "bulk book delete app state API"
require_pattern "$APP_STATE_FILE" 'prepareBulkBookDeletion:[[:space:]]*DatabaseManager\.makeBulkBookDeletionPlan\(bookIDs:\)' "live bulk book plan wiring"
require_pattern "$APP_STATE_FILE" 'deleteBooks:[[:space:]]*DatabaseManager\.deleteBooks\(using:\)' "live bulk book delete wiring"

require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+makeBulkBookDeletionPlan\(bookIDs:[[:space:]]*\[UUID\]\)' "database bulk book plan API"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+deleteBooks\(using[[:space:]]+plan:[[:space:]]*BulkBookDeletionPlan\)' "database bulk book delete API"
require_pattern "$DATABASE_FILE" 'let[[:space:]]+capturedBookIDs[[:space:]]*=[[:space:]]*try[[:space:]]+fetchLiveBookIDs' "captured live book set"
require_pattern "$DATABASE_FILE" 'let[[:space:]]+linkedHighlights[[:space:]]*=[[:space:]]*try[[:space:]]+fetchLiveLinkedHighlights' "captured linked highlight set"
require_pattern "$DATABASE_FILE" 'INSERT OR IGNORE INTO highlight_tombstones' "book delete tombstone insertion"
require_pattern "$DATABASE_FILE" 'DELETE FROM highlights' "linked highlight delete SQL"
require_pattern "$DATABASE_FILE" 'DELETE FROM books' "book delete SQL"
require_pattern "$DATABASE_FILE" 'plan\.linkedHighlightIDs' "captured linked highlight ID delete set"

cp "$ROOT_DIR/scripts/verify_t99_main.swift" "$TMP_DIR/main.swift"
cp "$ROOT_DIR/App/ScheduleSettings.swift" "$TMP_DIR/ScheduleSettings.swift"
cp "$ROOT_DIR/App/AppState.swift" "$TMP_DIR/AppState.swift"
cp "$ROOT_DIR/App/AppSupportPaths.swift" "$TMP_DIR/AppSupportPaths.swift"
cp "$ROOT_DIR/App/BackgroundImageStore.swift" "$TMP_DIR/BackgroundImageStore.swift"
cp "$ROOT_DIR/App/BackgroundImageLoader.swift" "$TMP_DIR/BackgroundImageLoader.swift"
cp "$ROOT_DIR/App/DebouncedTaskScheduler.swift" "$TMP_DIR/DebouncedTaskScheduler.swift"
cp "$ROOT_DIR/App/SettingsView.swift" "$TMP_DIR/SettingsView.swift"
cp "$ROOT_DIR/Models/Book.swift" "$TMP_DIR/Book.swift"
cp "$ROOT_DIR/Models/BulkBookDeletionPlan.swift" "$TMP_DIR/BulkBookDeletionPlan.swift"
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
  "$TMP_DIR/DebouncedTaskScheduler.swift" \
  "$TMP_DIR/SettingsView.swift" \
  "$TMP_DIR/Book.swift" \
  "$TMP_DIR/BulkBookDeletionPlan.swift" \
  "$TMP_DIR/Highlight.swift" \
  -o "$TMP_DIR/verify_t99_main"

"$TMP_DIR/verify_t99_main"

echo "T99 verification passed"
