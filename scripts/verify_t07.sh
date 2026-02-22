#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"

if [[ ! -f "$database_file" ]]; then
  echo "Database.swift is missing"
  exit 1
fi

if ! rg -q 'static func pickNextHighlight\(\) -> Highlight\?' "$database_file"; then
  echo "pickNextHighlight() signature is missing"
  exit 1
fi

if ! rg -q 'SELECT COUNT\(\*\)' "$database_file"; then
  echo "pickNextHighlight does not count highlights"
  exit 1
fi

if ! rg -q 'WHERE bookId IN \(SELECT id FROM books WHERE isEnabled = 1\)' "$database_file"; then
  echo "pickNextHighlight does not scope to enabled books"
  exit 1
fi

if ! rg -q 'AND lastShownAt IS NULL' "$database_file"; then
  echo "pickNextHighlight does not filter unshown highlights"
  exit 1
fi

if ! rg -q 'Int.random\(in: 0\.\.<eligibleCount\)' "$database_file"; then
  echo "pickNextHighlight does not use random offset"
  exit 1
fi

if ! rg -q 'LIMIT 1 OFFSET \?' "$database_file"; then
  echo "pickNextHighlight does not use LIMIT 1 OFFSET"
  exit 1
fi

if ! rg -q 'if eligibleCount == 0 \{' "$database_file"; then
  echo "pickNextHighlight does not handle exhausted pool"
  exit 1
fi

if ! rg -q 'UPDATE highlights' "$database_file"; then
  echo "pickNextHighlight does not reset highlights"
  exit 1
fi

if ! rg -q 'SET lastShownAt = NULL' "$database_file"; then
  echo "pickNextHighlight does not clear lastShownAt on reset"
  exit 1
fi

if ! rg -q 'guard activePoolCount > 0 else \{' "$database_file"; then
  echo "pickNextHighlight does not return nil for empty active pool"
  exit 1
fi

echo "T07 verification passed"
