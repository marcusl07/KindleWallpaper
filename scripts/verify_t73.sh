#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"
highlight_file="Models/Highlight.swift"
dedupe_file="Models/DedupeKeyBuilder.swift"
import_file="App/ImportCoordinator.swift"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file"
    exit 1
  fi
}

require_pattern "$highlight_file" 'let bookId: UUID\?' "nullable highlight bookId property"
require_pattern "$database_file" 'bookId[[:space:]]+TEXT,' "nullable highlights bookId column"
require_pattern "$database_file" 'registerMigration\("makeHighlightsBookIDNullable"\)' "bookId nullable migration"
require_pattern "$database_file" 'CREATE TABLE highlights_migrated' "rebuilt highlights table migration"
require_pattern "$database_file" 'bookId IS NULL OR bookId IN \(SELECT id FROM books WHERE isEnabled = 1\)' "manual quote active-pool predicate"
require_pattern "$database_file" 'highlight\.bookId\?\.uuidString' "nullable bookId insert binding"
require_pattern "$database_file" 'let bookIDValue: String\?' "nullable bookId row decoding"
require_pattern "$dedupe_file" 'static func makeKey\(' "dedupe key overload declaration"
require_pattern "$dedupe_file" 'bookId: UUID\?' "nullable dedupe key entrypoint"
require_pattern "$dedupe_file" 'manual\|' "manual quote dedupe namespace"
require_pattern "$import_file" 'let parsedBookID = highlight\.bookId' "optional parsed bookId handling"

tmp_dir="$(mktemp -d /tmp/kindlewall_t73.XXXXXX)"
trap 'rm -rf "$tmp_dir"' EXIT
db_file="$tmp_dir/t73.db"

sqlite3 "$db_file" <<'SQL'
CREATE TABLE books (
  id TEXT PRIMARY KEY,
  title TEXT NOT NULL,
  author TEXT NOT NULL,
  isEnabled INTEGER NOT NULL DEFAULT 1
);

CREATE TABLE highlights (
  id TEXT PRIMARY KEY,
  bookId TEXT NOT NULL,
  quoteText TEXT NOT NULL,
  bookTitle TEXT NOT NULL,
  author TEXT NOT NULL,
  location TEXT,
  dateAdded TEXT,
  lastShownAt TEXT,
  isEnabled INTEGER NOT NULL DEFAULT 1,
  dedupeKey TEXT NOT NULL UNIQUE
);

CREATE INDEX idx_highlights_bookId ON highlights(bookId);
CREATE INDEX idx_highlights_bookId_lastShownAt ON highlights(bookId, lastShownAt);

INSERT INTO books (id, title, author, isEnabled) VALUES
  ('enabled-book', 'Enabled Book', 'Author', 1),
  ('disabled-book', 'Disabled Book', 'Author', 0);

INSERT INTO highlights (id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled, dedupeKey) VALUES
  ('linked-unshown', 'enabled-book', 'Linked active', 'Enabled Book', 'Author', '1-2', '2026-01-01T00:00:00Z', NULL, 1, 'linked-unshown'),
  ('linked-shown', 'enabled-book', 'Linked shown', 'Enabled Book', 'Author', '3-4', '2026-01-01T00:00:00Z', '2026-02-01T00:00:00Z', 1, 'linked-shown'),
  ('linked-disabled-book', 'disabled-book', 'Disabled book quote', 'Disabled Book', 'Author', '5-6', '2026-01-01T00:00:00Z', '2026-02-02T00:00:00Z', 1, 'linked-disabled-book');
SQL

book_id_notnull_before="$(sqlite3 "$db_file" "SELECT \"notnull\" FROM pragma_table_info('highlights') WHERE name = 'bookId';")"
if [[ "$book_id_notnull_before" != "1" ]]; then
  echo "Expected legacy highlights.bookId to start as NOT NULL"
  exit 1
fi

sqlite3 "$db_file" <<'SQL'
CREATE TABLE highlights_migrated (
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

INSERT INTO highlights_migrated (
  id,
  bookId,
  quoteText,
  bookTitle,
  author,
  location,
  dateAdded,
  lastShownAt,
  isEnabled,
  dedupeKey
)
SELECT
  id,
  bookId,
  quoteText,
  bookTitle,
  author,
  location,
  dateAdded,
  lastShownAt,
  isEnabled,
  dedupeKey
FROM highlights;

DROP TABLE highlights;
ALTER TABLE highlights_migrated RENAME TO highlights;
CREATE INDEX idx_highlights_bookId ON highlights(bookId);
CREATE INDEX idx_highlights_bookId_lastShownAt ON highlights(bookId, lastShownAt);

INSERT INTO highlights (id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled, dedupeKey) VALUES
  ('manual-unshown', NULL, 'Manual active', '', '', NULL, '2026-03-01T00:00:00Z', NULL, 1, 'manual-unshown'),
  ('manual-disabled', NULL, 'Manual disabled', '', '', NULL, '2026-03-01T00:00:00Z', '2026-03-02T00:00:00Z', 0, 'manual-disabled');
SQL

book_id_notnull_after="$(sqlite3 "$db_file" "SELECT \"notnull\" FROM pragma_table_info('highlights') WHERE name = 'bookId';")"
if [[ "$book_id_notnull_after" != "0" ]]; then
  echo "Expected migrated highlights.bookId to be nullable"
  exit 1
fi

row_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM highlights;")"
if [[ "$row_count" != "5" ]]; then
  echo "Expected migration and manual inserts to preserve five highlight rows, got $row_count"
  exit 1
fi

index_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM sqlite_master WHERE type = 'index' AND name IN ('idx_highlights_bookId', 'idx_highlights_bookId_lastShownAt');")"
if [[ "$index_count" != "2" ]]; then
  echo "Expected highlights indexes to be recreated after migration"
  exit 1
fi

active_pool_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM highlights WHERE (bookId IS NULL OR bookId IN (SELECT id FROM books WHERE isEnabled = 1)) AND isEnabled = 1;")"
if [[ "$active_pool_count" != "3" ]]; then
  echo "Unexpected active pool count after nullable book migration: $active_pool_count"
  exit 1
fi

eligible_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM highlights WHERE (bookId IS NULL OR bookId IN (SELECT id FROM books WHERE isEnabled = 1)) AND isEnabled = 1 AND lastShownAt IS NULL;")"
if [[ "$eligible_count" != "2" ]]; then
  echo "Unexpected eligible count after nullable book migration: $eligible_count"
  exit 1
fi

sqlite3 "$db_file" "UPDATE highlights SET lastShownAt = NULL WHERE (bookId IS NULL OR bookId IN (SELECT id FROM books WHERE isEnabled = 1)) AND isEnabled = 1;"

linked_reset_value="$(sqlite3 "$db_file" "SELECT COALESCE(lastShownAt, 'NULL') FROM highlights WHERE id = 'linked-shown';")"
manual_reset_value="$(sqlite3 "$db_file" "SELECT COALESCE(lastShownAt, 'NULL') FROM highlights WHERE id = 'manual-unshown';")"
disabled_manual_reset_value="$(sqlite3 "$db_file" "SELECT COALESCE(lastShownAt, 'NULL') FROM highlights WHERE id = 'manual-disabled';")"
disabled_book_reset_value="$(sqlite3 "$db_file" "SELECT COALESCE(lastShownAt, 'NULL') FROM highlights WHERE id = 'linked-disabled-book';")"

if [[ "$linked_reset_value" != "NULL" ]]; then
  echo "Expected enabled-book quote to participate in reset path"
  exit 1
fi

if [[ "$manual_reset_value" != "NULL" ]]; then
  echo "Expected manual active quote to participate in reset path"
  exit 1
fi

if [[ "$disabled_manual_reset_value" != "2026-03-02T00:00:00Z" ]]; then
  echo "Expected disabled manual quote to remain untouched by reset path"
  exit 1
fi

if [[ "$disabled_book_reset_value" != "2026-02-02T00:00:00Z" ]]; then
  echo "Disabled-book quote should remain unchanged by the active-pool reset path"
  exit 1
fi

cp "$ROOT_DIR/scripts/verify_t73_main.swift" "$tmp_dir/main.swift"

swiftc \
  -module-cache-path "$tmp_dir/module-cache" \
  "$tmp_dir/main.swift" \
  "$ROOT_DIR/App/ImportCoordinator.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  "$ROOT_DIR/Models/DedupeKeyBuilder.swift" \
  -o "$tmp_dir/verify_t73_main"

"$tmp_dir/verify_t73_main"

echo "T73 verification passed"
