#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"

if [[ ! -f "$database_file" ]]; then
  echo "Database.swift is missing"
  exit 1
fi

if ! rg -q 'static func insertHighlightIfNew\(_ highlight: Highlight\)' "$database_file"; then
  echo "insertHighlightIfNew(_:) signature is missing"
  exit 1
fi

if ! rg -q 'let dedupeKey = computeDedupeKey\(for: highlight\)' "$database_file"; then
  echo "insertHighlightIfNew does not compute a dedupe key"
  exit 1
fi

if ! rg -q 'SELECT 1' "$database_file"; then
  echo "insertHighlightIfNew does not check for an existing row"
  exit 1
fi

if ! rg -q 'FROM highlights' "$database_file"; then
  echo "insertHighlightIfNew does not query the highlights table"
  exit 1
fi

if ! rg -q 'WHERE dedupeKey = \?' "$database_file"; then
  echo "insertHighlightIfNew does not query by dedupeKey"
  exit 1
fi

if ! rg -q 'guard !alreadyExists else' "$database_file"; then
  echo "insertHighlightIfNew does not skip duplicates"
  exit 1
fi

if ! rg -q 'INSERT INTO highlights' "$database_file"; then
  echo "insertHighlightIfNew does not insert highlights"
  exit 1
fi

if ! rg -q 'dedupeKey' "$database_file"; then
  echo "insertHighlightIfNew does not persist dedupeKey"
  exit 1
fi

if ! rg -q 'private static func computeDedupeKey\(for highlight: Highlight\) -> String' "$database_file"; then
  echo "computeDedupeKey helper is missing"
  exit 1
fi

if ! rg -q 'DedupeKeyBuilder\.makeKey' "$database_file"; then
  echo "insertHighlightIfNew does not use shared dedupe key computation"
  exit 1
fi

echo "T05 verification passed"
