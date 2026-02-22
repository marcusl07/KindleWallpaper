#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"

if [[ ! -f "$database_file" ]]; then
  echo "Database.swift is missing"
  exit 1
fi

if ! rg -q 'static func setBookEnabled\(id: UUID, enabled: Bool\)' "$database_file"; then
  echo "setBookEnabled(id:enabled:) signature is missing"
  exit 1
fi

if ! rg -q 'static func setAllBooksEnabled\(enabled: Bool\)' "$database_file"; then
  echo "setAllBooksEnabled(enabled:) signature is missing"
  exit 1
fi

if ! rg -q 'UPDATE books' "$database_file"; then
  echo "setBookEnabled does not update books"
  exit 1
fi

if ! rg -q 'SET isEnabled = \?' "$database_file"; then
  echo "setBookEnabled does not set isEnabled"
  exit 1
fi

if ! rg -q 'WHERE id = \?' "$database_file"; then
  echo "setBookEnabled does not filter by id"
  exit 1
fi

if ! rg -q 'if enabled \{' "$database_file"; then
  echo "setBookEnabled does not branch on enabled state"
  exit 1
fi

if ! rg -q 'UPDATE books' "$database_file"; then
  echo "setAllBooksEnabled does not update books"
  exit 1
fi

if ! rg -q 'UPDATE highlights' "$database_file"; then
  echo "setBookEnabled does not update highlights when enabling"
  exit 1
fi

if ! rg -q 'SET lastShownAt = NULL' "$database_file"; then
  echo "setBookEnabled does not reset highlight lastShownAt"
  exit 1
fi

if ! rg -q 'WHERE bookId = \?' "$database_file"; then
  echo "setBookEnabled does not filter highlights by bookId"
  exit 1
fi

if ! rg -q 'CREATE INDEX IF NOT EXISTS idx_highlights_bookId' "$database_file"; then
  echo "highlights bookId index is missing"
  exit 1
fi

echo "T06 verification passed"
