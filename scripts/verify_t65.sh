#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t65.XXXXXX)"
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

require_absent() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if rg -q "$pattern" "$file"; then
    echo "Verification failed: unexpected $description in $file" >&2
    exit 1
  fi
}

require_pattern "$SETTINGS_FILE" 'NavigationLink\(value:[[:space:]]*SettingsDestination\.books\)' "inline books navigation"
require_pattern "$SETTINGS_FILE" 'BooksListView\(\)' "books destination view"
require_absent "$SETTINGS_FILE" 'kindleWallShowBooksWindow' "books window notification constant"
require_absent "$APP_FILE" 'booksWindowController' "books window controller storage"
require_absent "$APP_FILE" 'booksWindowObserver' "books window observer storage"
require_absent "$APP_FILE" 'installBooksWindowObserver' "books notification observer installer"
require_absent "$APP_FILE" 'showBooksWindow\(' "books window presentation path"
require_absent "$APP_FILE" 'configureBooksWindow\(' "books window configuration path"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$ROOT_DIR/App/WallpaperHistoryPruner.swift" \
  "$ROOT_DIR/App/KindleWallApp.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

echo "T65 verification passed"
