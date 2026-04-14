#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t107a.XXXXXX)"
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

require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+let[[:space:]]+importPreflightBatchRowLimit' "import preflight batch-size limit"
require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+func[[:space:]]+fetchExistingImportTombstoneIdentityKeys' "bulk tombstone preflight helper"
require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+func[[:space:]]+fetchExistingHighlightDedupeKeys' "bulk dedupe preflight helper"
require_pattern "$DATABASE_FILE" 'WHERE quoteIdentityKey IN \(' "tombstone IN query"
require_pattern "$DATABASE_FILE" 'sqlPlaceholders\(count:[[:space:]]*quoteIdentityKeyBatch\.count\)' "tombstone batch placeholder count"
require_pattern "$DATABASE_FILE" 'WHERE dedupeKey IN \(' "dedupe IN query"
require_pattern "$DATABASE_FILE" 'sqlPlaceholders\(count:[[:space:]]*dedupeKeyBatch\.count\)' "dedupe batch placeholder count"

PERSIST_IMPORT_BLOCK="$TMP_DIR/persist_import.swift"
sed -n '/static func persistImport(/,/static func fetchAllBooks()/p' "$DATABASE_FILE" > "$PERSIST_IMPORT_BLOCK"

require_pattern "$PERSIST_IMPORT_BLOCK" 'fetchExistingImportTombstoneIdentityKeys' "persistImport tombstone preflight call"
require_pattern "$PERSIST_IMPORT_BLOCK" 'fetchExistingHighlightDedupeKeys' "persistImport dedupe preflight call"
require_pattern "$PERSIST_IMPORT_BLOCK" 'importHighlightRows\.append' "persistImport staged import highlight rows"
require_pattern "$PERSIST_IMPORT_BLOCK" 'knownDedupeKeys\.insert\(importHighlightRow\.dedupeKey\)\.inserted' "persistImport in-memory dedupe tracking"
require_pattern "$PERSIST_IMPORT_BLOCK" 'bulkInsertHighlightsForImport' "persistImport bulk insert after preflight"

forbid_pattern "$PERSIST_IMPORT_BLOCK" 'hasHighlightTombstone\(highlight:[[:space:]]*persistedHighlight' "per-highlight tombstone lookup inside persistImport"
forbid_pattern "$PERSIST_IMPORT_BLOCK" 'insertHighlightIfNew\(persistedHighlight' "per-highlight dedupe lookup inside persistImport"

echo "T107-a verification passed"
