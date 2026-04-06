#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
DATABASE_FILE="$ROOT_DIR/App/Database.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t80.XXXXXX)"
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

require_pattern "$DATABASE_FILE" 'static func setHighlightEnabled\(id: UUID, enabled: Bool\)' "database highlight toggle entrypoint"
require_pattern "$DATABASE_FILE" 'UPDATE highlights' "highlight update SQL"
require_pattern "$DATABASE_FILE" 'SET isEnabled = \?' "highlight enabled-state SQL"
require_pattern "$DATABASE_FILE" 'SET lastShownAt = NULL' "highlight re-enable reset SQL"
require_pattern "$APP_STATE_FILE" 'typealias SetHighlightEnabled = \(UUID, Bool\) -> Void' "app-state highlight toggle typealias"
require_pattern "$APP_STATE_FILE" 'func setHighlightEnabled\(id: UUID, enabled: Bool\)' "app-state highlight toggle API"
require_pattern "$SETTINGS_FILE" 'Button\(Self\.toggleButtonTitle\(isEnabled: highlight\.isEnabled\)\)' "detail view enable-disable button"
require_pattern "$SETTINGS_FILE" 'QuoteDetailViewTestProbe' "detail view test probe"

cp "$ROOT_DIR/scripts/verify_t80_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t80_main"

"$TMP_DIR/verify_t80_main"

echo "T80 verification passed"
