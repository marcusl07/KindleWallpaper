#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"

if [[ ! -f "$database_file" ]]; then
  echo "Database.swift is missing"
  exit 1
fi

if ! rg -q 'static func markHighlightShown\(id: UUID\)' "$database_file"; then
  echo "markHighlightShown(id:) signature is missing"
  exit 1
fi

if ! rg -q 'UPDATE highlights' "$database_file"; then
  echo "markHighlightShown does not update highlights"
  exit 1
fi

if ! rg -q 'SET lastShownAt = \?' "$database_file"; then
  echo "markHighlightShown does not set lastShownAt"
  exit 1
fi

if ! rg -q 'WHERE id = \?' "$database_file"; then
  echo "markHighlightShown does not filter by highlight id"
  exit 1
fi

if ! rg -q 'iso8601Formatter\.string\(from: Date\(\)\)' "$database_file"; then
  echo "markHighlightShown does not write a current ISO8601 timestamp"
  exit 1
fi

if ! rg -q 'formatter\.formatOptions = \[\.withInternetDateTime, \.withFractionalSeconds\]' "$database_file"; then
  echo "ISO8601 formatter options are not configured for timezone-aware internet date-time output"
  exit 1
fi

echo "T08 verification passed"
