#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"
highlight_file="Models/Highlight.swift"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file"
    exit 1
  fi
}

require_pattern "$database_file" 'DatabaseMigrator' "database migrator"
require_pattern "$database_file" 'ALTER TABLE highlights' "highlights isEnabled migration"
require_pattern "$database_file" 'ADD COLUMN isEnabled INTEGER NOT NULL DEFAULT 1' "highlights isEnabled column migration"
require_pattern "$database_file" 'isEnabled   INTEGER NOT NULL DEFAULT 1' "highlights isEnabled create-table column"
require_pattern "$database_file" 'AND isEnabled = 1' "highlight-level enabled filtering in rotation queries"
require_pattern "$highlight_file" 'let isEnabled: Bool' "highlight isEnabled property"
require_pattern "$highlight_file" 'isEnabled: Bool = true' "highlight isEnabled default initializer"

tmp_dir="$(mktemp -d /tmp/kindlewall_t72.XXXXXX)"
db_file="$tmp_dir/t72.db"
trap 'rm -rf "$tmp_dir"' EXIT

sqlite3 "$db_file" <<'SQL'
CREATE TABLE books (
  id TEXT PRIMARY KEY,
  isEnabled INTEGER NOT NULL
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
  dedupeKey TEXT NOT NULL UNIQUE
);

CREATE INDEX idx_highlights_bookId ON highlights(bookId);
CREATE INDEX idx_highlights_bookId_lastShownAt ON highlights(bookId, lastShownAt);

WITH RECURSIVE seq(x) AS (
  SELECT 1
  UNION ALL
  SELECT x + 1 FROM seq WHERE x < 200
)
INSERT INTO books(id, isEnabled)
SELECT
  printf('book-%04d', x),
  CASE WHEN x <= 100 THEN 1 ELSE 0 END
FROM seq;

WITH RECURSIVE seq(x) AS (
  SELECT 1
  UNION ALL
  SELECT x + 1 FROM seq WHERE x < 10000
)
INSERT INTO highlights(id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, dedupeKey)
SELECT
  printf('hl-%05d', x),
  printf('book-%04d', ((x - 1) % 200) + 1),
  'Quote',
  'Book',
  'Author',
  printf('%d-%d', x, x + 1),
  '2026-01-01T00:00:00Z',
  CASE WHEN x % 4 = 0 THEN '2026-02-01T00:00:00Z' ELSE NULL END,
  printf('dedupe-%05d', x)
FROM seq;
SQL

pre_migration_columns="$(sqlite3 "$db_file" "PRAGMA table_info(highlights);")"
if grep -q 'isEnabled' <<<"$pre_migration_columns"; then
  echo "Pre-migration highlights schema unexpectedly already contains isEnabled"
  exit 1
fi

sqlite3 "$db_file" 'ALTER TABLE highlights ADD COLUMN isEnabled INTEGER NOT NULL DEFAULT 1;'

post_migration_columns="$(sqlite3 "$db_file" "PRAGMA table_info(highlights);")"
if ! grep -q 'isEnabled' <<<"$post_migration_columns"; then
  echo "Migration did not add highlights.isEnabled"
  exit 1
fi

existing_row_default_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM highlights WHERE isEnabled = 1;")"
if [[ "$existing_row_default_count" != "10000" ]]; then
  echo "Expected migrated rows to default isEnabled to 1, got $existing_row_default_count"
  exit 1
fi

sqlite3 "$db_file" <<'SQL'
UPDATE highlights
SET isEnabled = 0
WHERE CAST(substr(id, 4) AS INTEGER) % 5 = 0;
SQL

active_pool_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1) AND isEnabled = 1;")"
if [[ "$active_pool_count" != "4000" ]]; then
  echo "Unexpected active pool count with highlight filter: $active_pool_count"
  exit 1
fi

eligible_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1) AND isEnabled = 1 AND lastShownAt IS NULL;")"
if [[ "$eligible_count" != "3000" ]]; then
  echo "Unexpected eligible count with highlight filter: $eligible_count"
  exit 1
fi

selected_id="$(sqlite3 "$db_file" "SELECT id FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1) AND isEnabled = 1 AND lastShownAt IS NULL LIMIT 1 OFFSET 123;")"
if [[ -z "$selected_id" ]]; then
  echo "Eligible pick query failed with highlight enablement filter"
  exit 1
fi

active_pool_plan="$(sqlite3 "$db_file" "EXPLAIN QUERY PLAN SELECT COUNT(*) FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1) AND isEnabled = 1;")"
if ! grep -Eq 'USING (COVERING )?INDEX idx_highlights_bookId(_lastShownAt)?' <<<"$active_pool_plan"; then
  echo "Active pool query plan did not use an existing highlights index"
  echo "$active_pool_plan"
  exit 1
fi

eligible_pick_plan="$(sqlite3 "$db_file" "EXPLAIN QUERY PLAN SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1) AND isEnabled = 1 AND lastShownAt IS NULL LIMIT 1 OFFSET 123;")"
if ! grep -q 'USING INDEX idx_highlights_bookId_lastShownAt' <<<"$eligible_pick_plan"; then
  echo "Eligible pick query plan did not use idx_highlights_bookId_lastShownAt"
  echo "$eligible_pick_plan"
  exit 1
fi

echo "T72 verification passed"
