#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t114a.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" '^struct[[:space:]]+QuotesListFilters' "shared quotes filters type"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchHighlightsPage\(' "paged highlights fetch API"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchAvailableHighlightBookTitles\(' "book filter options API"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchAvailableHighlightAuthors\(' "author filter options API"
require_pattern "$DATABASE_FILE" 'CREATE INDEX IF NOT EXISTS idx_highlights_alphabetical_sort' "alphabetical paging index"
require_pattern "$DATABASE_FILE" 'CREATE INDEX IF NOT EXISTS idx_highlights_most_recent_sort' "most-recent paging index"
require_pattern "$DATABASE_FILE" 'registerMigration\("addHighlightPagingIndexes"\)' "paging index migration"
require_pattern "$DATABASE_FILE" 'quoteText LIKE \? COLLATE NOCASE' "quote search predicate"
require_pattern "$DATABASE_FILE" 'bookTitle LIKE \? COLLATE NOCASE' "book-title search predicate"
require_pattern "$DATABASE_FILE" 'author LIKE \? COLLATE NOCASE' "author search predicate"
require_pattern "$DATABASE_FILE" 'bookId IS NULL' "manual-only predicate"
require_pattern "$DATABASE_FILE" 'bookId IN \(SELECT id FROM books WHERE isEnabled = 1\)' "enabled-books predicate"
require_pattern "$DATABASE_FILE" 'bookId IN \(SELECT id FROM books WHERE isEnabled = 0\)' "disabled-books predicate"
require_pattern "$DATABASE_FILE" 'SELECT DISTINCT .* AS value' "distinct filter options query"
require_pattern "$DATABASE_FILE" 'ORDER BY value COLLATE NOCASE ASC' "distinct filter options ordering"
require_pattern "$DATABASE_FILE" 'LIMIT \? OFFSET \?' "paged fetch limit and offset"

DB_FILE="$TMP_DIR/t114a.db"

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
  ('book-enabled', 'Alpha', 'Author A', 1),
  ('book-disabled', 'Beta', 'Author B', 0);

INSERT INTO highlights (id, bookId, quoteText, bookTitle, author, dateAdded, dedupeKey) VALUES
  ('1', 'book-enabled', 'Needle in quote body', 'Alpha', 'Author A', '2026-04-01T10:00:00Z', 'd1'),
  ('2', NULL, 'Manual note', '', 'Author A', '2026-04-02T10:00:00Z', 'd2'),
  ('3', 'book-disabled', 'Other text', 'Beta', 'Author B', '2026-04-03T10:00:00Z', 'd3'),
  ('4', NULL, 'Different text', '', '', '2026-04-04T10:00:00Z', 'd4');
SQL

book_options="$(sqlite3 "$DB_FILE" <<'SQL'
SELECT group_concat(value, '|')
FROM (
  SELECT DISTINCT
    CASE
      WHEN TRIM(bookTitle) = '' THEN 'Unknown Book'
      ELSE TRIM(bookTitle)
    END AS value
  FROM highlights
  WHERE
    CASE
      WHEN TRIM(author) = '' THEN 'Unknown Author'
      ELSE TRIM(author)
    END = 'Author A'
  ORDER BY value COLLATE NOCASE ASC
);
SQL
)"

if [[ "$book_options" != "Alpha|Unknown Book" ]]; then
  echo "Verification failed: unexpected cross-dimension book options: $book_options" >&2
  exit 1
fi

author_options="$(sqlite3 "$DB_FILE" <<'SQL'
SELECT group_concat(value, '|')
FROM (
  SELECT DISTINCT
    CASE
      WHEN TRIM(author) = '' THEN 'Unknown Author'
      ELSE TRIM(author)
    END AS value
  FROM highlights
  WHERE
    CASE
      WHEN TRIM(bookTitle) = '' THEN 'Unknown Book'
      ELSE TRIM(bookTitle)
    END = 'Unknown Book'
  ORDER BY value COLLATE NOCASE ASC
);
SQL
)"

if [[ "$author_options" != "Author A|Unknown Author" ]]; then
  echo "Verification failed: unexpected cross-dimension author options: $author_options" >&2
  exit 1
fi

search_page_ids="$(sqlite3 "$DB_FILE" <<'SQL'
SELECT group_concat(id, ',')
FROM (
  SELECT id
  FROM highlights
  WHERE (
    quoteText LIKE '%needle%' COLLATE NOCASE
    OR bookTitle LIKE '%needle%' COLLATE NOCASE
    OR author LIKE '%needle%' COLLATE NOCASE
  )
  ORDER BY
    bookTitle COLLATE NOCASE ASC,
    author COLLATE NOCASE ASC,
    quoteText COLLATE NOCASE ASC,
    id ASC
  LIMIT 100 OFFSET 0
);
SQL
)"

if [[ "$search_page_ids" != "1" ]]; then
  echo "Verification failed: unexpected paged search result ids: $search_page_ids" >&2
  exit 1
fi

disabled_ids="$(sqlite3 "$DB_FILE" <<'SQL'
SELECT group_concat(id, ',')
FROM (
  SELECT id
  FROM highlights
  WHERE
    bookId IS NOT NULL
    AND bookId IN (SELECT id FROM books WHERE isEnabled = 0)
  ORDER BY
    bookTitle COLLATE NOCASE ASC,
    author COLLATE NOCASE ASC,
    quoteText COLLATE NOCASE ASC,
    id ASC
);
SQL
)"

if [[ "$disabled_ids" != "3" ]]; then
  echo "Verification failed: unexpected disabled-book filtered ids: $disabled_ids" >&2
  exit 1
fi

echo "T114-a verification passed"
