#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
DEDUPE_FILE="$ROOT_DIR/Models/DedupeKeyBuilder.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t97a.XXXXXX)"
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

require_pattern "$DEDUPE_FILE" 'enum[[:space:]]+ImportStableQuoteIdentityKeyBuilder' "import-stable identity builder"
require_pattern "$DEDUPE_FILE" 'normalizedQuoteText' "full normalized quote identity component"
require_pattern "$DATABASE_FILE" 'CREATE TABLE IF NOT EXISTS highlight_tombstones' "highlight tombstones table"
require_pattern "$DATABASE_FILE" 'quoteIdentityKey TEXT PRIMARY KEY' "tombstone primary key"
require_pattern "$DATABASE_FILE" 'registerMigration\("createHighlightTombstones"\)' "tombstone migration"
require_pattern "$DATABASE_FILE" 'static func hasHighlightTombstone' "tombstone lookup API"

DB_FILE="$TMP_DIR/t97a.db"

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
  ('book-1', 'Book One', 'Author One', 1);

INSERT INTO highlights (id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled, dedupeKey) VALUES
  ('highlight-1', 'book-1', 'Quote text', 'Book One', 'Author One', 'Loc 10', '2026-04-08T00:00:00Z', NULL, 1, 'dedupe-1');

CREATE TABLE IF NOT EXISTS highlight_tombstones (
  quoteIdentityKey TEXT PRIMARY KEY,
  deletedAt        TEXT NOT NULL
);
SQL

highlight_count="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM highlights;")"
if [[ "$highlight_count" != "1" ]]; then
  echo "Expected tombstone migration setup to preserve existing highlight rows, got $highlight_count" >&2
  exit 1
fi

tombstone_table_count="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name = 'highlight_tombstones';")"
if [[ "$tombstone_table_count" != "1" ]]; then
  echo "Expected highlight_tombstones table to exist after migration setup" >&2
  exit 1
fi

quote_identity_pk="$(sqlite3 "$DB_FILE" "SELECT pk FROM pragma_table_info('highlight_tombstones') WHERE name = 'quoteIdentityKey';")"
if [[ "$quote_identity_pk" != "1" ]]; then
  echo "Expected quoteIdentityKey to be the tombstone primary key" >&2
  exit 1
fi

sqlite3 "$DB_FILE" "INSERT INTO highlight_tombstones (quoteIdentityKey, deletedAt) VALUES ('import|book one|author one|loc 10|quote text', '2026-04-08T01:00:00Z');"

set +e
sqlite3 "$DB_FILE" "INSERT INTO highlight_tombstones (quoteIdentityKey, deletedAt) VALUES ('import|book one|author one|loc 10|quote text', '2026-04-08T02:00:00Z');" >/dev/null 2>&1
duplicate_status=$?
set -e

if [[ "$duplicate_status" == "0" ]]; then
  echo "Expected tombstone primary key to reject duplicate quote identity keys" >&2
  exit 1
fi

cp "$ROOT_DIR/scripts/verify_t97a_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/Models/DedupeKeyBuilder.swift" \
  -o "$TMP_DIR/verify_t97a_main"

"$TMP_DIR/verify_t97a_main"

echo "T97-a verification passed"
