#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t81.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'typealias[[:space:]]+DeleteHighlight[[:space:]]*=[[:space:]]*\(UUID\)[[:space:]]*->[[:space:]]*Void' "delete highlight typealias"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+deleteHighlight\(id:[[:space:]]*UUID\)' "delete highlight app state API"
require_pattern "$APP_STATE_FILE" 'deleteHighlight:[[:space:]]*DatabaseManager\.deleteHighlight\(id:\)' "live delete highlight wiring"
require_pattern "$DATABASE_FILE" 'static[[:space:]]+func[[:space:]]+deleteHighlight\(id:[[:space:]]*UUID\)' "database delete highlight API"
require_pattern "$DATABASE_FILE" 'DELETE FROM highlights' "highlight delete SQL"
require_pattern "$SETTINGS_FILE" 'Button\("Delete Quote",[[:space:]]*role:[[:space:]]*\.destructive\)' "detail view delete button"
require_pattern "$SETTINGS_FILE" '\.alert\("Delete Quote\?"' "delete confirmation alert"
require_pattern "$SETTINGS_FILE" 'appState\.deleteHighlight\(id:[[:space:]]*highlight\.id\)' "detail view delete action wiring"
require_pattern "$SETTINGS_FILE" 'dismiss\(\)' "detail view dismissal after delete"

cp "$ROOT_DIR/scripts/verify_t81_main.swift" "$TMP_DIR/main.swift"
cp "$ROOT_DIR/App/ScheduleSettings.swift" "$TMP_DIR/ScheduleSettings.swift"
cp "$ROOT_DIR/App/AppState.swift" "$TMP_DIR/AppState.swift"
cp "$ROOT_DIR/App/AppSupportPaths.swift" "$TMP_DIR/AppSupportPaths.swift"
cp "$ROOT_DIR/App/BackgroundImageStore.swift" "$TMP_DIR/BackgroundImageStore.swift"
cp "$ROOT_DIR/App/BackgroundImageLoader.swift" "$TMP_DIR/BackgroundImageLoader.swift"
cp "$ROOT_DIR/App/SettingsView.swift" "$TMP_DIR/SettingsView.swift"
cp "$ROOT_DIR/Models/Book.swift" "$TMP_DIR/Book.swift"
cp "$ROOT_DIR/Models/Highlight.swift" "$TMP_DIR/Highlight.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$TMP_DIR/ScheduleSettings.swift" \
  "$TMP_DIR/AppState.swift" \
  "$TMP_DIR/AppSupportPaths.swift" \
  "$TMP_DIR/BackgroundImageStore.swift" \
  "$TMP_DIR/BackgroundImageLoader.swift" \
  "$TMP_DIR/SettingsView.swift" \
  "$TMP_DIR/Book.swift" \
  "$TMP_DIR/Highlight.swift" \
  -o "$TMP_DIR/verify_t81_main"

"$TMP_DIR/verify_t81_main"

echo "T81 verification passed"
