#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t102.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" '@State[[:space:]]+private[[:space:]]+var[[:space:]]+pendingBulkDeletePlan:[[:space:]]+BulkHighlightDeletionPlan\?' "captured quote bulk-delete plan state"
require_pattern "$SETTINGS_FILE" 'let[[:space:]]+plan[[:space:]]*=[[:space:]]*appState\.prepareBulkHighlightDeletion\(highlightIDs:[[:space:]]*highlightIDsToDelete\)' "captured selected quote plan before confirmation"
require_pattern "$SETTINGS_FILE" 'confirmBulkDeleteHighlights\(\)' "confirmed quote bulk-delete action"
require_pattern "$SETTINGS_FILE" 'bulkDeleteConfirmationTitle\(' "count-based quote bulk-delete confirmation title"
require_pattern "$SETTINGS_FILE" 'bulkDeleteConfirmationMessage\(' "count-based quote bulk-delete confirmation message"
require_pattern "$SETTINGS_FILE" 'guard[[:space:]]+let[[:space:]]+plan[[:space:]]*=[[:space:]]*pendingBulkDeletePlan' "confirmed delete captures pending quote plan"
require_pattern "$SETTINGS_FILE" 'appState\.deleteHighlights\(using:[[:space:]]*plan\)' "confirmed delete uses captured quote plan"
require_pattern "$SETTINGS_FILE" 'QuotesListViewTestProbe' "quote test probe exposure"

cp "$ROOT_DIR/scripts/verify_t102_main.swift" "$TMP_DIR/main.swift"
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
  -o "$TMP_DIR/verify_t102_main"

"$TMP_DIR/verify_t102_main"

echo "T102 verification passed"
