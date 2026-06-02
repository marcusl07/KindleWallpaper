#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file" >&2
    exit 1
  fi
}

# 1. Verify code matches expected FTS5 patterns
require_pattern "$DATABASE_FILE" 'createHighlightsFTSTableSQL' "FTS5 table SQL declaration"
require_pattern "$DATABASE_FILE" 'populateHighlightsFTSSQL' "FTS5 population SQL declaration"
require_pattern "$DATABASE_FILE" 'createHighlightsFTSInsertTriggerSQL' "FTS5 insert trigger SQL declaration"
require_pattern "$DATABASE_FILE" 'createHighlightsFTSDeleteTriggerSQL' "FTS5 delete trigger SQL declaration"
require_pattern "$DATABASE_FILE" 'createHighlightsFTSUpdateTriggerSQL' "FTS5 update trigger SQL declaration"
require_pattern "$DATABASE_FILE" 'registerMigration\("addHighlightsFTS"\)' "addHighlightsFTS migration registration"
require_pattern "$DATABASE_FILE" 'highlights\.rowid IN \(SELECT rowid FROM highlights_fts WHERE highlights_fts MATCH \?\)' "FTS5 MATCH query usage"

# 2. Setup SQLite tests
TMP_DIR="$(mktemp -d /tmp/kindlewall_fts.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT
DB_FILE="$TMP_DIR/fts_test.db"

# Create pre-migration DB
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

INSERT INTO books (id, title, author, isEnabled) VALUES
  ('b1', 'The Hobbit', 'J.R.R. Tolkien', 1),
  ('b2', '1984', 'George Orwell', 1);

INSERT INTO highlights (id, bookId, quoteText, bookTitle, author, dedupeKey) VALUES
  ('h1', 'b1', 'In a hole in the ground there lived a hobbit.', 'The Hobbit', 'J.R.R. Tolkien', 'd1'),
  ('h2', 'b2', 'It was a bright cold day in April, and the clocks were striking thirteen.', '1984', 'George Orwell', 'd2');
SQL

# Run FTS5 migrations
sqlite3 "$DB_FILE" <<'SQL'
PRAGMA trusted_schema = 1;

-- FTS5 table
CREATE VIRTUAL TABLE highlights_fts USING fts5(
    quoteText,
    bookTitle,
    author,
    content='highlights'
);

-- Populate existing
INSERT INTO highlights_fts(rowid, quoteText, bookTitle, author)
SELECT rowid, quoteText, bookTitle, author FROM highlights;

-- Triggers
CREATE TRIGGER highlights_ai AFTER INSERT ON highlights BEGIN
    INSERT INTO highlights_fts(rowid, quoteText, bookTitle, author)
    VALUES (new.rowid, new.quoteText, new.bookTitle, new.author);
END;

CREATE TRIGGER highlights_ad AFTER DELETE ON highlights BEGIN
    INSERT INTO highlights_fts(highlights_fts, rowid, quoteText, bookTitle, author)
    VALUES ('delete', old.rowid, old.quoteText, old.bookTitle, old.author);
END;

CREATE TRIGGER highlights_au AFTER UPDATE ON highlights BEGIN
    INSERT INTO highlights_fts(highlights_fts, rowid, quoteText, bookTitle, author)
    VALUES ('delete', old.rowid, old.quoteText, old.bookTitle, old.author);
    INSERT INTO highlights_fts(rowid, quoteText, bookTitle, author)
    VALUES (new.rowid, new.quoteText, new.bookTitle, new.author);
END;
SQL

# Check population
fts_row_count="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM highlights_fts;")"
if [[ "$fts_row_count" != "2" ]]; then
  echo "FTS5 table not populated correctly, expected 2 rows, got $fts_row_count" >&2
  exit 1
fi

# Test Search Match
search_result="$(sqlite3 "$DB_FILE" "SELECT id FROM highlights WHERE rowid IN (SELECT rowid FROM highlights_fts WHERE highlights_fts MATCH 'hobbit*');")"
if [[ "$search_result" != "h1" ]]; then
  echo "FTS5 search query failed: expected h1, got $search_result" >&2
  exit 1
fi

# Test FTS Insert Trigger
sqlite3 "$DB_FILE" <<'SQL'
PRAGMA trusted_schema = 1;
INSERT INTO highlights (id, bookId, quoteText, bookTitle, author, dedupeKey)
VALUES ('h3', 'b2', 'War is peace. Freedom is slavery. Ignorance is strength.', '1984', 'George Orwell', 'd3');
SQL

search_result="$(sqlite3 "$DB_FILE" "SELECT id FROM highlights WHERE rowid IN (SELECT rowid FROM highlights_fts WHERE highlights_fts MATCH 'ignorance*');")"
if [[ "$search_result" != "h3" ]]; then
  echo "FTS5 Insert Trigger failed, expected h3 to match 'ignorance*'" >&2
  exit 1
fi

# Test FTS Update Trigger
sqlite3 "$DB_FILE" <<'SQL'
PRAGMA trusted_schema = 1;
UPDATE highlights
SET quoteText = 'War is peace. Freedom is slavery. Ignorance is knowledge.'
WHERE id = 'h3';
SQL

search_result_old="$(sqlite3 "$DB_FILE" "SELECT id FROM highlights WHERE rowid IN (SELECT rowid FROM highlights_fts WHERE highlights_fts MATCH 'strength*');")"
search_result_new="$(sqlite3 "$DB_FILE" "SELECT id FROM highlights WHERE rowid IN (SELECT rowid FROM highlights_fts WHERE highlights_fts MATCH 'knowledge*');")"

if [[ -n "$search_result_old" ]]; then
  echo "FTS5 Update Trigger failed to delete old text, got match for 'strength*'" >&2
  exit 1
fi
if [[ "$search_result_new" != "h3" ]]; then
  echo "FTS5 Update Trigger failed to insert new text, expected h3 for 'knowledge*'" >&2
  exit 1
fi

# Test FTS Delete Trigger
sqlite3 "$DB_FILE" <<'SQL'
PRAGMA trusted_schema = 1;
DELETE FROM highlights WHERE id = 'h3';
SQL

search_result_del="$(sqlite3 "$DB_FILE" "SELECT id FROM highlights WHERE rowid IN (SELECT rowid FROM highlights_fts WHERE highlights_fts MATCH 'knowledge*');")"
if [[ -n "$search_result_del" ]]; then
  echo "FTS5 Delete Trigger failed, expected no matches for deleted highlight" >&2
  exit 1
fi

# Test Swift string query helper
swift "$ROOT_DIR/scripts/verify_fts_main.swift"

echo "FTS integration tests passed successfully!"
