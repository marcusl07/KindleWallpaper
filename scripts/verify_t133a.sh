#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file" >&2
    exit 1
  fi
}

require_pattern "$DATABASE_FILE" 'deleteSelectionBatchRowLimit' "delete batch row limit"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+deleteRows\(' "batched delete helper"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+forEachStringBatch\(' "shared string batch helper"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchHighlightsByID\(' "batched highlight capture helper"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchExistingBookIDSet\(' "batched book-id capture helper"
require_pattern "$DATABASE_FILE" 'linkedHighlights\.sort\(by:[[:space:]]*bulkBookDeletionLinkedHighlightSort\)' "batched linked-highlight global sort"
require_pattern "$DATABASE_FILE" 'from:[[:space:]]*"highlights"' "highlight delete uses batched helper"
require_pattern "$DATABASE_FILE" 'from:[[:space:]]*"books"' "book delete uses batched helper"

cd "$ROOT_DIR"
xcodebuild -project KindleWall.xcodeproj -scheme KindleWall -sdk macosx build >/tmp/kindlewall_t133a_xcodebuild.log

echo "T133-a verification passed"
