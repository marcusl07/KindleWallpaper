#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"

if [[ ! -f "$database_file" ]]; then
  echo "Database.swift is missing"
  exit 1
fi

if ! rg -q 'static func totalHighlightCount\(\) -> Int' "$database_file"; then
  echo "totalHighlightCount() signature is missing"
  exit 1
fi

if ! rg -q 'SELECT COUNT\(\*\)' "$database_file"; then
  echo "totalHighlightCount does not use COUNT(*)"
  exit 1
fi

if ! rg -q 'FROM highlights' "$database_file"; then
  echo "totalHighlightCount does not query highlights"
  exit 1
fi

echo "T10 verification passed"
