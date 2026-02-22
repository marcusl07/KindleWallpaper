#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

database_file="App/Database.swift"
project_file="KindleWall.xcodeproj/project.pbxproj"

if [[ ! -f "$database_file" ]]; then
  echo "Database.swift is missing"
  exit 1
fi

if ! rg -q 'static let shared: DatabaseQueue' "$database_file"; then
  echo "Shared DatabaseQueue is missing"
  exit 1
fi

if ! rg -q 'homeDirectoryForCurrentUser' "$database_file"; then
  echo "Database path does not use the home directory"
  exit 1
fi

if ! rg -q 'appendingPathComponent\("Library"' "$database_file"; then
  echo "Database path missing Library component"
  exit 1
fi

if ! rg -q 'appendingPathComponent\("Application Support"' "$database_file"; then
  echo "Database path missing Application Support component"
  exit 1
fi

if ! rg -q 'appendingPathComponent\("KindleWall"' "$database_file"; then
  echo "Database path missing KindleWall component"
  exit 1
fi

if ! rg -q 'appendingPathComponent\("highlights\.db"' "$database_file"; then
  echo "Database path missing highlights.db filename"
  exit 1
fi

if ! rg -q 'CREATE TABLE IF NOT EXISTS books' "$database_file"; then
  echo "Books table creation SQL is missing"
  exit 1
fi

if ! rg -q 'UNIQUE\(title, author\)' "$database_file"; then
  echo "Books UNIQUE(title, author) constraint is missing"
  exit 1
fi

if ! rg -q 'CREATE TABLE IF NOT EXISTS highlights' "$database_file"; then
  echo "Highlights table creation SQL is missing"
  exit 1
fi

if ! rg -q 'dedupeKey\s+TEXT NOT NULL UNIQUE' "$database_file"; then
  echo "Highlights dedupeKey unique constraint is missing"
  exit 1
fi

if ! rg -q 'Database\.swift in Sources' "$project_file"; then
  echo "Database.swift is not part of target sources"
  exit 1
fi

echo "T03 verification passed"
