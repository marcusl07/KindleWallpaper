#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"

if [[ ! -f "$database_file" ]]; then
  echo "Database.swift is missing"
  exit 1
fi

if ! rg -q 'CREATE INDEX IF NOT EXISTS idx_highlights_bookId_lastShownAt' "$database_file"; then
  echo "Composite highlight index declaration is missing"
  exit 1
fi

if ! rg -q 'ON highlights\(bookId, lastShownAt\);' "$database_file"; then
  echo "Composite highlight index columns are incorrect"
  exit 1
fi

if ! rg -q 'createHighlightsBookIDLastShownAtIndexSQL' "$database_file"; then
  echo "Composite highlight index is not wired into schema initialization"
  exit 1
fi

tmp_dir="$(mktemp -d /tmp/kindlewall_t52.XXXXXX)"
db_file="$tmp_dir/t52.db"
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
INSERT INTO highlights(id, bookId, quoteText, bookTitle, author, lastShownAt, dedupeKey)
SELECT
  printf('hl-%05d', x),
  printf('book-%04d', ((x - 1) % 200) + 1),
  'Quote',
  'Book',
  'Author',
  CASE WHEN x % 4 = 0 THEN '2026-01-01T00:00:00Z' ELSE NULL END,
  printf('dedupe-%05d', x)
FROM seq;
SQL

active_pool_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1);")"
if [[ "$active_pool_count" != "5000" ]]; then
  echo "Unexpected active pool count: $active_pool_count"
  exit 1
fi

eligible_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1) AND lastShownAt IS NULL;")"
if [[ "$eligible_count" != "3750" ]]; then
  echo "Unexpected eligible count: $eligible_count"
  exit 1
fi

selected_id="$(sqlite3 "$db_file" "SELECT id FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1) AND lastShownAt IS NULL LIMIT 1 OFFSET 123;")"
if [[ -z "$selected_id" ]]; then
  echo "Eligible pick query failed to return a row at non-zero offset"
  exit 1
fi

active_pool_plan="$(sqlite3 "$db_file" "EXPLAIN QUERY PLAN SELECT COUNT(*) FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1);")"
if ! grep -Eq 'USING (COVERING )?INDEX idx_highlights_bookId(_lastShownAt)?' <<<"$active_pool_plan"; then
  echo "Active pool query plan did not use a highlights bookId index"
  echo "$active_pool_plan"
  exit 1
fi

eligible_pick_plan="$(sqlite3 "$db_file" "EXPLAIN QUERY PLAN SELECT id, bookId, quoteText, bookTitle, author, lastShownAt FROM highlights WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1) AND lastShownAt IS NULL LIMIT 1 OFFSET 123;")"
if ! grep -q 'USING INDEX idx_highlights_bookId_lastShownAt' <<<"$eligible_pick_plan"; then
  echo "Eligible pick query plan did not use idx_highlights_bookId_lastShownAt"
  echo "$eligible_pick_plan"
  exit 1
fi

echo "T52 verification passed"
