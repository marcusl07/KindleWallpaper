#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t112a.XXXXXX)"
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

require_pattern "$DATABASE_FILE" 'CREATE INDEX IF NOT EXISTS idx_highlights_bookTitle_nocase' "book title sort index"
require_pattern "$DATABASE_FILE" 'CREATE INDEX IF NOT EXISTS idx_highlights_author_nocase' "author sort index"
require_pattern "$DATABASE_FILE" 'CREATE INDEX IF NOT EXISTS idx_highlights_dateAdded' "date-added sort index"
require_pattern "$DATABASE_FILE" 'registerMigration\("addHighlightSortIndexes"\)' "sort index migration"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchAllHighlights\(sortedBy[[:space:]]+sortMode:[[:space:]]*QuotesListSortMode' "sort-aware highlight fetch API"
require_pattern "$DATABASE_FILE" 'ORDER BY \\\(highlightsOrderClause\(sortedBy:[[:space:]]*sortMode\)\)' "sort-aware SQL order clause"
require_pattern "$DATABASE_FILE" 'bookTitle COLLATE NOCASE ASC' "alphabetical book ordering"
require_pattern "$DATABASE_FILE" 'author COLLATE NOCASE ASC' "alphabetical author ordering"
require_pattern "$DATABASE_FILE" 'quoteText COLLATE NOCASE ASC' "alphabetical quote ordering"
require_pattern "$DATABASE_FILE" 'CASE WHEN dateAdded IS NULL THEN 1 ELSE 0 END ASC' "null-last recent ordering prelude"
require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+FetchAllHighlights[[:space:]]*=[[:space:]]*\(QuotesListSortMode\)[[:space:]]*->[[:space:]]*\[Highlight\]' "sort-aware app state fetch boundary"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+loadAllHighlights\(sortedBy[[:space:]]+sortMode:[[:space:]]*QuotesListSortMode[[:space:]]*=[[:space:]]*\.mostRecentlyAdded\)' "sort-aware app state load API"
require_pattern "$SETTINGS_FILE" 'appState\.loadAllHighlights\(sortedBy:[[:space:]]*sortMode\)' "quotes view sort-aware refresh"
require_pattern "$SETTINGS_FILE" '\.onChange\(of:[[:space:]]*sortMode\)' "quotes view sort change refresh"

TYPECHECK_FILES=(
  $(cd "$ROOT_DIR" && rg --files App Models Parsing -g '*.swift' | rg -v '^App/Database\.swift$')
)

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  -typecheck \
  "${TYPECHECK_FILES[@]/#/$ROOT_DIR/}"

DB_FILE="$TMP_DIR/t112a_sorting.db"

sqlite3 "$DB_FILE" <<'SQL'
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

INSERT INTO highlights (id, quoteText, bookTitle, author, dateAdded, dedupeKey) VALUES
  ('2', 'Zulu quote', 'Zoo', 'Anne', '2026-04-01T10:00:00Z', 'd2'),
  ('3', 'alpha quote', 'apple', 'Beth', NULL, 'd3'),
  ('1', 'Beta quote', 'Banana', 'Chris', '2026-04-03T10:00:00Z', 'd1'),
  ('4', 'aardvark quote', 'banana', 'alex', '2026-04-03T10:00:00Z', 'd4');
SQL

most_recent_ids="$(sqlite3 "$DB_FILE" <<'SQL'
SELECT group_concat(id, ',')
FROM (
  SELECT id
  FROM highlights
  ORDER BY
    CASE WHEN dateAdded IS NULL THEN 1 ELSE 0 END ASC,
    dateAdded DESC,
    bookTitle COLLATE NOCASE ASC,
    author COLLATE NOCASE ASC,
    quoteText COLLATE NOCASE ASC,
    id ASC
);
SQL
)"

if [[ "$most_recent_ids" != "4,1,2,3" ]]; then
  echo "Verification failed: unexpected most-recent order: $most_recent_ids" >&2
  exit 1
fi

alphabetical_ids="$(sqlite3 "$DB_FILE" <<'SQL'
SELECT group_concat(id, ',')
FROM (
  SELECT id
  FROM highlights
  ORDER BY
    bookTitle COLLATE NOCASE ASC,
    author COLLATE NOCASE ASC,
    quoteText COLLATE NOCASE ASC,
    id ASC
);
SQL
)"

if [[ "$alphabetical_ids" != "3,4,1,2" ]]; then
  echo "Verification failed: unexpected alphabetical order: $alphabetical_ids" >&2
  exit 1
fi

echo "T112-a verification passed"
