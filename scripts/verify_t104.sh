#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
IMPORT_COORDINATOR_FILE="$ROOT_DIR/App/ImportCoordinator.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t104.XXXXXX)"
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

require_pattern "$IMPORT_COORDINATOR_FILE" 'guard[[:space:]]+highlightHasTombstone\(persistedHighlight\)[[:space:]]*==[[:space:]]*false[[:space:]]+else' "tombstone suppression guard before insert"
require_pattern "$IMPORT_COORDINATOR_FILE" 'insertHighlightIfNew\(persistedHighlight\)' "persisted highlight insertion path"

require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+deleteBooks\(using[[:space:]]+plan:[[:space:]]*BulkBookDeletionPlan\)' "bulk book delete API"
require_pattern "$DATABASE_FILE" 'try[[:space:]]+shared\.write[[:space:]]*\{[[:space:]]*database[[:space:]]+in' "transactional database write wrapper"
require_pattern "$DATABASE_FILE" 'INSERT OR IGNORE INTO highlight_tombstones' "book delete tombstone write"
require_pattern "$DATABASE_FILE" 'DELETE FROM highlights' "linked highlight delete SQL"
require_pattern "$DATABASE_FILE" 'DELETE FROM books' "book delete SQL"

require_pattern "$SETTINGS_FILE" 'QuotesListViewTestProbe' "quote bulk-delete test probe"
require_pattern "$SETTINGS_FILE" 'BooksListViewTestProbe' "book bulk-delete test probe"
require_pattern "$SETTINGS_FILE" 'bulkDeleteConfirmationTitle' "bulk-delete confirmation count helper"
require_pattern "$SETTINGS_FILE" 'bulkDeleteButtonDisabled' "bulk-delete disabled-state helper"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+loadAllHighlights\(\)[[:space:]]*->[[:space:]]*\[Highlight\]' "highlight refresh API for selection reconciliation"

DB_FILE="$TMP_DIR/t104_rollback.db"

sqlite3 "$DB_FILE" <<'SQL'
CREATE TABLE books (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  isEnabled INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE highlights (
  id TEXT PRIMARY KEY,
  bookId TEXT,
  quoteText TEXT NOT NULL,
  bookTitle TEXT NOT NULL,
  author TEXT NOT NULL,
  location TEXT,
  dateAdded TEXT,
  lastShownAt TEXT,
  isEnabled INTEGER NOT NULL DEFAULT 1,
  dedupeKey TEXT NOT NULL UNIQUE
);

CREATE TABLE highlight_tombstones (
  quoteIdentityKey TEXT PRIMARY KEY,
  deletedAt TEXT NOT NULL
);

INSERT INTO books (id, title, author, isEnabled) VALUES
  ('book-1', 'Rollback Book', 'Rollback Author', 1);

INSERT INTO highlights (id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled, dedupeKey) VALUES
  ('highlight-1', 'book-1', 'Rollback Quote', 'Rollback Book', 'Rollback Author', 'Loc 1', '2026-04-08T00:00:00Z', NULL, 1, 'dedupe-rollback');

CREATE TRIGGER prevent_book_delete
BEFORE DELETE ON books
BEGIN
  SELECT RAISE(ROLLBACK, 'simulated bulk delete failure');
END;
SQL

set +e
sqlite3 "$DB_FILE" <<'SQL' >/dev/null 2>&1
BEGIN IMMEDIATE;
INSERT OR IGNORE INTO highlight_tombstones (quoteIdentityKey, deletedAt)
VALUES ('import|rollback book|rollback author|loc 1|rollback quote', '2026-04-08T01:00:00Z');
DELETE FROM highlights
WHERE id IN ('highlight-1');
DELETE FROM books
WHERE id IN ('book-1');
COMMIT;
SQL
transaction_status=$?
set -e

if [[ "$transaction_status" == "0" ]]; then
  echo "Expected simulated bulk delete transaction to fail" >&2
  exit 1
fi

remaining_book_count="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM books WHERE id = 'book-1';")"
remaining_highlight_count="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM highlights WHERE id = 'highlight-1';")"
tombstone_count="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM highlight_tombstones;")"

if [[ "$remaining_book_count" != "1" ]]; then
  echo "Expected failed transaction to preserve the book row, got $remaining_book_count" >&2
  exit 1
fi

if [[ "$remaining_highlight_count" != "1" ]]; then
  echo "Expected failed transaction to preserve the linked highlight row, got $remaining_highlight_count" >&2
  exit 1
fi

if [[ "$tombstone_count" != "0" ]]; then
  echo "Expected failed transaction to roll back tombstone writes, got $tombstone_count" >&2
  exit 1
fi

cp "$ROOT_DIR/scripts/verify_t104_main.swift" "$TMP_DIR/main.swift"
cp "$ROOT_DIR/App/ScheduleSettings.swift" "$TMP_DIR/ScheduleSettings.swift"
cp "$ROOT_DIR/App/AppState.swift" "$TMP_DIR/AppState.swift"
cp "$ROOT_DIR/App/AppSupportPaths.swift" "$TMP_DIR/AppSupportPaths.swift"
cp "$ROOT_DIR/App/BackgroundImageStore.swift" "$TMP_DIR/BackgroundImageStore.swift"
cp "$ROOT_DIR/App/BackgroundImageLoader.swift" "$TMP_DIR/BackgroundImageLoader.swift"
cp "$ROOT_DIR/App/ImportCoordinator.swift" "$TMP_DIR/ImportCoordinator.swift"
cp "$ROOT_DIR/App/SettingsView.swift" "$TMP_DIR/SettingsView.swift"
cp "$ROOT_DIR/Models/Book.swift" "$TMP_DIR/Book.swift"
cp "$ROOT_DIR/Models/BulkBookDeletionPlan.swift" "$TMP_DIR/BulkBookDeletionPlan.swift"
cp "$ROOT_DIR/Models/DedupeKeyBuilder.swift" "$TMP_DIR/DedupeKeyBuilder.swift"
cp "$ROOT_DIR/Models/Highlight.swift" "$TMP_DIR/Highlight.swift"
cp "$ROOT_DIR/Parsing/ClippingsParser.swift" "$TMP_DIR/ClippingsParser.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$TMP_DIR/ScheduleSettings.swift" \
  "$TMP_DIR/AppState.swift" \
  "$TMP_DIR/AppSupportPaths.swift" \
  "$TMP_DIR/BackgroundImageStore.swift" \
  "$TMP_DIR/BackgroundImageLoader.swift" \
  "$TMP_DIR/ImportCoordinator.swift" \
  "$TMP_DIR/SettingsView.swift" \
  "$TMP_DIR/Book.swift" \
  "$TMP_DIR/BulkBookDeletionPlan.swift" \
  "$TMP_DIR/DedupeKeyBuilder.swift" \
  "$TMP_DIR/Highlight.swift" \
  "$TMP_DIR/ClippingsParser.swift" \
  -o "$TMP_DIR/verify_t104_main"

"$TMP_DIR/verify_t104_main"

echo "T104 verification passed"
