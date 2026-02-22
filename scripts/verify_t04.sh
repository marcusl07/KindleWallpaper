#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"

if [[ ! -f "$database_file" ]]; then
  echo "Database.swift is missing"
  exit 1
fi

if ! rg -q 'static func upsertBook\(_ book: Book\) -> UUID' "$database_file"; then
  echo "upsertBook(_: ) signature is missing"
  exit 1
fi

if ! rg -q 'INSERT OR IGNORE INTO books' "$database_file"; then
  echo "upsertBook does not use INSERT OR IGNORE"
  exit 1
fi

if ! rg -q 'id, title, author, isEnabled' "$database_file"; then
  echo "upsertBook insert columns are incomplete"
  exit 1
fi

if ! rg -q 'SELECT id' "$database_file"; then
  echo "upsertBook does not query for existing id"
  exit 1
fi

if ! rg -q 'WHERE title = \? AND author = \?' "$database_file"; then
  echo "upsertBook does not query by (title, author)"
  exit 1
fi

if ! rg -q 'String\.fetchOne' "$database_file"; then
  echo "upsertBook does not fetch an existing id value"
  exit 1
fi

if ! rg -q 'UUID\(uuidString:' "$database_file"; then
  echo "upsertBook does not convert stored id string to UUID"
  exit 1
fi

echo "T04 verification passed"
