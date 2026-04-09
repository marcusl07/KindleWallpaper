#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t115a.XXXXXX)"
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

fetch_segment_ids() {
  local db_file="$1"
  local date_condition="$2"
  local order_clause="$3"
  local limit="$4"
  local offset="$5"

  sqlite3 "$db_file" <<SQL
SELECT group_concat(id, ',')
FROM (
  SELECT id
  FROM highlights
  WHERE $date_condition
  ORDER BY $order_clause
  LIMIT $limit OFFSET $offset
);
SQL
}

fetch_most_recent_page_ids() {
  local db_file="$1"
  local limit="$2"
  local offset="$3"
  local dated_order="dateAdded DESC, bookTitle COLLATE NOCASE ASC, author COLLATE NOCASE ASC, quoteText COLLATE NOCASE ASC, id ASC"
  local null_order="bookTitle COLLATE NOCASE ASC, author COLLATE NOCASE ASC, quoteText COLLATE NOCASE ASC, id ASC"
  local non_null_count
  local page_ids=""

  non_null_count="$(sqlite3 "$db_file" "SELECT COUNT(*) FROM highlights WHERE dateAdded IS NOT NULL;")"

  if (( offset < non_null_count )); then
    page_ids="$(fetch_segment_ids "$db_file" "dateAdded IS NOT NULL" "$dated_order" "$limit" "$offset")"
    local fetched_count=0
    if [[ -n "$page_ids" ]]; then
      fetched_count="$(tr ',' '\n' <<<"$page_ids" | sed '/^$/d' | wc -l | tr -d ' ')"
    fi

    if (( fetched_count < limit )); then
      local remaining_limit=$((limit - fetched_count))
      local null_ids
      null_ids="$(fetch_segment_ids "$db_file" "dateAdded IS NULL" "$null_order" "$remaining_limit" 0)"
      if [[ -n "$null_ids" ]]; then
        if [[ -n "$page_ids" ]]; then
          page_ids="$page_ids,$null_ids"
        else
          page_ids="$null_ids"
        fi
      fi
    fi
  else
    page_ids="$(fetch_segment_ids "$db_file" "dateAdded IS NULL" "$null_order" "$limit" "$((offset - non_null_count))")"
  fi

  printf '%s\n' "$page_ids"
}

require_pattern "$DATABASE_FILE" 'idx_highlights_most_recent_non_null_sort' "non-null most-recent sort index"
require_pattern "$DATABASE_FILE" 'registerMigration\("addHighlightMostRecentNonNullSortIndex"\)' "non-null most-recent migration"
require_pattern "$DATABASE_FILE" 'fetchMostRecentHighlightsPage\(' "segmented most-recent paging helper"
require_pattern "$DATABASE_FILE" 'fetchHighlightsCount\(' "non-null segment count helper"
require_pattern "$DATABASE_FILE" 'dateAdded IS NOT NULL' "non-null dated segment predicate"
require_pattern "$DATABASE_FILE" 'dateAdded IS NULL' "null dated segment predicate"
require_pattern "$DATABASE_FILE" 'offset - nonNullDateCount' "null-segment offset adjustment"
require_pattern "$DATABASE_FILE" 'remainingLimit = limit - highlights.count' "cross-boundary remainder calculation"

DB_FILE="$TMP_DIR/t115a.db"

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

CREATE INDEX idx_highlights_alphabetical_sort
ON highlights(
  bookTitle COLLATE NOCASE,
  author COLLATE NOCASE,
  quoteText COLLATE NOCASE,
  id
);

CREATE INDEX idx_highlights_most_recent_non_null_sort
ON highlights(
  dateAdded DESC,
  bookTitle COLLATE NOCASE,
  author COLLATE NOCASE,
  quoteText COLLATE NOCASE,
  id
)
WHERE dateAdded IS NOT NULL;

INSERT INTO highlights (id, quoteText, bookTitle, author, dateAdded, dedupeKey) VALUES
  ('1', 'Newest', 'Gamma', 'Author C', '2026-04-05T10:00:00Z', 'd1'),
  ('2', 'Middle', 'Alpha', 'Author A', '2026-04-04T10:00:00Z', 'd2'),
  ('3', 'Oldest dated', 'Beta', 'Author B', '2026-04-03T10:00:00Z', 'd3'),
  ('4', 'Null first', 'Alpha', 'Author A', NULL, 'd4'),
  ('5', 'Null second', 'Delta', 'Author D', NULL, 'd5');
SQL

page_0_ids="$(fetch_most_recent_page_ids "$DB_FILE" 2 0)"
page_1_ids="$(fetch_most_recent_page_ids "$DB_FILE" 2 2)"
page_2_ids="$(fetch_most_recent_page_ids "$DB_FILE" 2 4)"
boundary_ids="$(fetch_most_recent_page_ids "$DB_FILE" 2 3)"

if [[ "$page_0_ids" != "1,2" ]]; then
  echo "Verification failed: unexpected first page ids: $page_0_ids" >&2
  exit 1
fi

if [[ "$page_1_ids" != "3,4" ]]; then
  echo "Verification failed: unexpected cross-boundary page ids: $page_1_ids" >&2
  exit 1
fi

if [[ "$page_2_ids" != "5" ]]; then
  echo "Verification failed: unexpected null-segment page ids: $page_2_ids" >&2
  exit 1
fi

if [[ "$boundary_ids" != "4,5" ]]; then
  echo "Verification failed: unexpected exact-boundary page ids: $boundary_ids" >&2
  exit 1
fi

query_plan="$(sqlite3 "$DB_FILE" <<'SQL'
EXPLAIN QUERY PLAN
SELECT id
FROM highlights
WHERE dateAdded IS NOT NULL
ORDER BY
  dateAdded DESC,
  bookTitle COLLATE NOCASE ASC,
  author COLLATE NOCASE ASC,
  quoteText COLLATE NOCASE ASC,
  id ASC
LIMIT 2 OFFSET 0;
SQL
)"

if [[ "$query_plan" != *"idx_highlights_most_recent_non_null_sort"* ]]; then
  echo "Verification failed: non-null recent query plan did not use the partial sort index: $query_plan" >&2
  exit 1
fi

if [[ "$query_plan" == *"USE TEMP B-TREE FOR ORDER BY"* ]]; then
  echo "Verification failed: non-null recent query still used a temp B-tree: $query_plan" >&2
  exit 1
fi

echo "T115-a verification passed"
