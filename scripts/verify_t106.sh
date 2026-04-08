#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t106.XXXXXX)"
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

require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+let[[:space:]]+tombstoneInsertBatchRowLimit' "tombstone batch size limit"
require_pattern "$DATABASE_FILE" 'private[[:space:]]+static[[:space:]]+func[[:space:]]+insertHighlightTombstones' "shared tombstone batch helper"
require_pattern "$DATABASE_FILE" 'Array\(repeating:[[:space:]]*"\(\?, \?\)"[[:space:]]*,[[:space:]]*count:[[:space:]]*tombstoneBatch\.count\)' "batched tombstone VALUES SQL"
require_pattern "$DATABASE_FILE" 'StatementArguments\(tombstoneBatch\.flatMap[[:space:]]*\{[[:space:]]*\[\$0,[[:space:]]*deletedAt\][[:space:]]*\}\)' "batched tombstone arguments"
require_pattern "$DATABASE_FILE" 'uniqueStringsPreservingOrder' "stable dedupe before tombstone insert"

helper_call_count="$(rg -c 'try[[:space:]]+insertHighlightTombstones' "$DATABASE_FILE")"
if [[ "$helper_call_count" != "2" ]]; then
  echo "Verification failed: expected both delete flows to call the shared tombstone helper, got $helper_call_count calls" >&2
  exit 1
fi

insert_count="$(rg -c 'INSERT OR IGNORE INTO highlight_tombstones' "$DATABASE_FILE")"
if [[ "$insert_count" != "1" ]]; then
  echo "Verification failed: expected one shared highlight_tombstones insert SQL path, got $insert_count" >&2
  exit 1
fi

DB_FILE="$TMP_DIR/t106_batch.db"

sqlite3 "$DB_FILE" <<'SQL'
CREATE TABLE highlight_tombstones (
  quoteIdentityKey TEXT PRIMARY KEY,
  deletedAt TEXT NOT NULL
);

INSERT OR IGNORE INTO highlight_tombstones (quoteIdentityKey, deletedAt)
VALUES
  ('import|book one|author one|loc 1|quote one', '2026-04-08T01:00:00Z'),
  ('import|book one|author one|loc 1|quote one', '2026-04-08T02:00:00Z'),
  ('import|book two|author two|quote two', '2026-04-08T03:00:00Z');
SQL

tombstone_count="$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM highlight_tombstones;")"
if [[ "$tombstone_count" != "2" ]]; then
  echo "Expected batched tombstone insert to ignore duplicate identities, got $tombstone_count rows" >&2
  exit 1
fi

retained_deleted_at="$(sqlite3 "$DB_FILE" "SELECT deletedAt FROM highlight_tombstones WHERE quoteIdentityKey = 'import|book one|author one|loc 1|quote one';")"
if [[ "$retained_deleted_at" != "2026-04-08T01:00:00Z" ]]; then
  echo "Expected duplicate tombstone insert to preserve the original deletedAt, got $retained_deleted_at" >&2
  exit 1
fi

echo "T106 verification passed"
