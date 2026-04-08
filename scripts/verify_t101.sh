#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t101.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" '@State[[:space:]]+private[[:space:]]+var[[:space:]]+selectedBookIDs:[[:space:]]+Set<UUID>' "book bulk-delete selection state"
require_pattern "$SETTINGS_FILE" '@State[[:space:]]+private[[:space:]]+var[[:space:]]+isEditingBooks' "book edit-mode state"
require_pattern "$SETTINGS_FILE" 'List\(selection:[[:space:]]*\$selectedBookIDs\)' "editable multi-select book list"
require_pattern "$SETTINGS_FILE" 'Label\("Delete Selected",[[:space:]]*systemImage:[[:space:]]*"trash"\)' "book bulk-delete toolbar action"
require_pattern "$SETTINGS_FILE" 'reconcileSelectedBooks\(\)' "book selection reconciliation"
require_pattern "$SETTINGS_FILE" 'prepareBulkBookDeletion\(bookIDs:[[:space:]]*bookIDsToDelete\)' "bulk book deletion plan capture"
require_pattern "$SETTINGS_FILE" 'deleteBooks\(using:[[:space:]]*plan\)' "bulk book delete execution"
require_pattern "$SETTINGS_FILE" 'BooksListViewTestProbe' "book selection test probe"

cp "$ROOT_DIR/scripts/verify_t101_main.swift" "$TMP_DIR/main.swift"
cp "$ROOT_DIR/App/ScheduleSettings.swift" "$TMP_DIR/ScheduleSettings.swift"
cp "$ROOT_DIR/App/AppState.swift" "$TMP_DIR/AppState.swift"
cp "$ROOT_DIR/App/AppSupportPaths.swift" "$TMP_DIR/AppSupportPaths.swift"
cp "$ROOT_DIR/App/BackgroundImageStore.swift" "$TMP_DIR/BackgroundImageStore.swift"
cp "$ROOT_DIR/App/BackgroundImageLoader.swift" "$TMP_DIR/BackgroundImageLoader.swift"
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
  "$TMP_DIR/SettingsView.swift" \
  "$TMP_DIR/Book.swift" \
  "$TMP_DIR/BulkBookDeletionPlan.swift" \
  "$TMP_DIR/Highlight.swift" \
  -o "$TMP_DIR/verify_t101_main"

"$TMP_DIR/verify_t101_main"

echo "T101 verification passed"
