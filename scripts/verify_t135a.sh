#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t135a.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+PrepareBulkHighlightDeletion[[:space:]]*=[[:space:]]*\(\[UUID\]\)[[:space:]]*->[[:space:]]*BulkHighlightDeletionPlan' "bulk highlight deletion plan typealias"
require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+DeleteCapturedHighlights[[:space:]]*=[[:space:]]*\(BulkHighlightDeletionPlan\)[[:space:]]*->[[:space:]]*LibrarySnapshot' "captured highlight delete typealias"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+prepareBulkHighlightDeletion\(highlightIDs:[[:space:]]*\[UUID\]\)' "bulk highlight deletion plan app state API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+deleteHighlights\(using[[:space:]]+plan:[[:space:]]*BulkHighlightDeletionPlan\)' "captured highlight delete app state API"
require_pattern "$DATABASE_FILE" 'deleteSelectionBatchRowLimit' "delete batch row limit"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+deleteRows\(' "batched delete helper"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+forEachStringBatch\(' "shared string batch helper"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchHighlightsByID\(' "batched highlight capture helper"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchExistingBookIDSet\(' "batched book-id capture helper"
require_pattern "$DATABASE_FILE" 'from:[[:space:]]*"highlights"' "highlight delete uses batched helper"
require_pattern "$DATABASE_FILE" 'from:[[:space:]]*"books"' "book delete uses batched helper"
require_pattern "$SETTINGS_FILE" '@State[[:space:]]+private[[:space:]]+var[[:space:]]+pendingBulkDeletePlan:[[:space:]]+BulkHighlightDeletionPlan\?' "captured quote bulk-delete plan state"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+plan[[:space:]]*=[[:space:]]*appState\.prepareBulkHighlightDeletion\(highlightIDs:[[:space:]]*highlightIDsToDelete\)' "quote delete plan capture before confirmation"
require_pattern "$SETTINGS_FILE" 'appState\.deleteHighlights\(using:[[:space:]]*plan\)' "quote confirmation uses captured plan"
require_pattern "$SETTINGS_FILE" 'reconciledPendingDeletionPlan' "pending delete plan reconciliation helpers"
require_pattern "$SETTINGS_FILE" '@State[[:space:]]+private[[:space:]]+var[[:space:]]+pendingBulkBookDeletionPlan:[[:space:]]+BulkBookDeletionPlan\?' "captured book bulk-delete plan state"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+plan[[:space:]]*=[[:space:]]*appState\.prepareBulkBookDeletion\(bookIDs:[[:space:]]*bookIDsToDelete\)' "book delete plan capture before confirmation"
require_pattern "$SETTINGS_FILE" 'appState\.deleteBooks\(using:[[:space:]]*plan\)' "book confirmation uses captured plan"

cp "$ROOT_DIR/scripts/verify_t135a_main.swift" "$TMP_DIR/main.swift"
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
  -o "$TMP_DIR/verify_t135a_main"

"$TMP_DIR/verify_t135a_main"

bash "$ROOT_DIR/scripts/verify_t98.sh"
bash "$ROOT_DIR/scripts/verify_t99.sh"
bash "$ROOT_DIR/scripts/verify_t103.sh"
bash "$ROOT_DIR/scripts/verify_t104.sh"
bash "$ROOT_DIR/scripts/verify_t133a.sh"
bash "$ROOT_DIR/scripts/verify_t134a.sh"

echo "T135-a verification passed"
