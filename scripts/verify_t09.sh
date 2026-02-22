#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"

if [[ ! -f "$database_file" ]]; then
  echo "Database.swift is missing"
  exit 1
fi

if ! rg -q 'static func fetchAllBooks\(\) -> \[Book\]' "$database_file"; then
  echo "fetchAllBooks() signature is missing"
  exit 1
fi

if ! rg -q 'FROM books' "$database_file"; then
  echo "fetchAllBooks does not query books"
  exit 1
fi

if ! rg -q 'SELECT COUNT\(\*\)' "$database_file"; then
  echo "fetchAllBooks does not derive highlight counts"
  exit 1
fi

if ! rg -q 'AS highlightCount' "$database_file"; then
  echo "fetchAllBooks does not alias derived highlight count"
  exit 1
fi

if ! rg -q 'ORDER BY books\.title COLLATE NOCASE ASC' "$database_file"; then
  echo "fetchAllBooks does not sort alphabetically by title"
  exit 1
fi

if ! rg -q 'highlightCount: highlightCountValue' "$database_file"; then
  echo "fetchAllBooks does not map highlightCount into Book"
  exit 1
fi

echo "T09 verification passed"
