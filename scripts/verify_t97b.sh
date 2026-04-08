#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
IMPORT_FILE="$ROOT_DIR/App/ImportCoordinator.swift"
IDENTITY_FILE="$ROOT_DIR/Models/DedupeKeyBuilder.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t97b.XXXXXX)"
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

require_pattern "$IDENTITY_FILE" 'enum ImportStableQuoteIdentityKeyBuilder' "import-stable identity builder"
require_pattern "$DATABASE_FILE" 'INSERT OR IGNORE INTO highlight_tombstones' "tombstone insertion on delete"
require_pattern "$DATABASE_FILE" 'computeImportStableQuoteIdentity' "stable identity computation"
require_pattern "$IMPORT_FILE" 'typealias HighlightHasTombstone' "import tombstone dependency"
require_pattern "$IMPORT_FILE" 'guard highlightHasTombstone\(persistedHighlight\) == false else' "tombstone suppression guard"
require_pattern "$IMPORT_FILE" 'DatabaseManager\.hasHighlightTombstone' "live database tombstone lookup"

cp "$ROOT_DIR/scripts/verify_t97b_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -parse-as-library \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/ImportCoordinator.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  "$ROOT_DIR/Models/DedupeKeyBuilder.swift" \
  "$ROOT_DIR/Parsing/ClippingsParser.swift" \
  -o "$TMP_DIR/verify_t97b_main"

"$TMP_DIR/verify_t97b_main"

echo "T97-b verification passed"
