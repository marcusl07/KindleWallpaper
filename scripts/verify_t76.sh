#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t76.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+FetchAllHighlights' "highlight fetch dependency"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+loadAllHighlights\(\)[[:space:]]*->[[:space:]]*\[Highlight\]' "app state highlight loader"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+fetchAllHighlights\(\)[[:space:]]*->[[:space:]]*\[Highlight\]' "database highlight fetcher"
require_pattern "$SETTINGS_FILE" 'enum[[:space:]]+QuotesListSortMode' "quotes sort mode enum"
require_pattern "$SETTINGS_FILE" 'Picker\("Sort"' "quotes sort picker"
require_pattern "$SETTINGS_FILE" 'searchable\(text:[[:space:]]*\$searchText' "quotes search field"
require_pattern "$SETTINGS_FILE" 'List\(displayedHighlights\)' "filtered quotes list"
require_pattern "$SETTINGS_FILE" 'lineLimit\(2\)' "truncated quote row"
require_pattern "$SETTINGS_FILE" 'QuotesListViewTestProbe' "quotes test probe"

cp "$ROOT_DIR/scripts/verify_t76_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t76_main"

"$TMP_DIR/verify_t76_main"

echo "T76 verification passed"
