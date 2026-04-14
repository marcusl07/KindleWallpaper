#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t108a.XXXXXX)"
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

forbid_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if rg -q "$pattern" "$file"; then
    echo "Verification failed: unexpected $description in $file" >&2
    exit 1
  fi
}

require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+let[[:space:]]+importBookUpsertBatchRowLimit' "import book batch-size limit"
require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+let[[:space:]]+importHighlightInsertBatchRowLimit' "import highlight batch-size limit"
require_pattern "$DATABASE_FILE" 'private[[:space:]]+struct[[:space:]]+ImportHighlightInsertRow' "staged import highlight row type"
require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+func[[:space:]]+bulkUpsertBooksForImport' "bulk book upsert helper"
require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+func[[:space:]]+fetchPersistedImportBookIDs' "persisted import book lookup helper"
require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+func[[:space:]]+bulkInsertHighlightsForImport' "bulk highlight insert helper"
require_pattern "$DATABASE_FILE" 'INSERT OR IGNORE INTO books \(id, title, author, isEnabled\)' "bulk book insert SQL"
require_pattern "$DATABASE_FILE" 'WITH import_books\(parsedID, title, author\) AS \(' "import book lookup CTE"
require_pattern "$DATABASE_FILE" 'INSERT INTO highlights \(' "bulk highlight insert SQL"

PERSIST_IMPORT_BLOCK="$TMP_DIR/persist_import.swift"
sed -n '/static func persistImport(/,/static func fetchAllBooks()/p' "$DATABASE_FILE" > "$PERSIST_IMPORT_BLOCK"

require_pattern "$PERSIST_IMPORT_BLOCK" 'let[[:space:]]+persistedBookIDsByParsedID[[:space:]]*=[[:space:]]*try[[:space:]]+bulkUpsertBooksForImport' "bulk book upsert usage inside persistImport"
require_pattern "$PERSIST_IMPORT_BLOCK" 'ImportHighlightInsertRow' "staged import rows inside persistImport"
require_pattern "$PERSIST_IMPORT_BLOCK" 'let[[:space:]]+insertedHighlightCount[[:space:]]*=[[:space:]]*try[[:space:]]+bulkInsertHighlightsForImport' "bulk highlight insert usage inside persistImport"
require_pattern "$PERSIST_IMPORT_BLOCK" 'newHighlightCount:[[:space:]]*insertedHighlightCount' "direct inserted-count reporting"

forbid_pattern "$PERSIST_IMPORT_BLOCK" 'let[[:space:]]+beforeCount[[:space:]]*=' "before-import total count scan in persistImport"
forbid_pattern "$PERSIST_IMPORT_BLOCK" 'let[[:space:]]+afterCount[[:space:]]*=' "after-import total count scan in persistImport"
forbid_pattern "$PERSIST_IMPORT_BLOCK" 'try[[:space:]]+upsertBook\(book,[[:space:]]*database:[[:space:]]*database\)' "row-by-row book upsert in persistImport"
forbid_pattern "$PERSIST_IMPORT_BLOCK" 'try[[:space:]]+insertHighlight\(' "row-by-row highlight insert in persistImport"

echo "T108-a verification passed"
