#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"

require_pattern() {
  local pattern="$1"
  local description="$2"

  if ! rg -q "$pattern" "$APP_FILE"; then
    echo "Verification failed: missing $description in App/KindleWallApp.swift" >&2
    exit 1
  fi
}

require_exact_count() {
  local pattern="$1"
  local expected_count="$2"
  local description="$3"

  local count
  count="$(rg -o "$pattern" "$APP_FILE" | wc -l | tr -d ' ')"
  if [[ "$count" != "$expected_count" ]]; then
    echo "Verification failed: expected $expected_count occurrences of $description, found $count" >&2
    exit 1
  fi
}

# T47 expectation: one shared main-thread status publisher, reused across listener variants.
require_pattern "let[[:space:]]+publishImportStatusOnMain:[[:space:]]+VolumeWatcher\\.PublishImportStatus[[:space:]]*=[[:space:]]*\\{[[:space:]]+status[[:space:]]+in" "shared import-status publisher"
require_pattern "DispatchQueue\\.main\\.async" "main-thread dispatch in shared publisher"
require_exact_count "publishImportStatus:[[:space:]]*publishImportStatusOnMain" "2" "shared publisher wiring"
require_exact_count "appState\\.setImportStatus\\(" "1" "setImportStatus update path"
require_exact_count "appState\\.refreshLibraryState\\(" "1" "refreshLibraryState update path"

TMP_DIR="$(mktemp -d /tmp/kindlewall_t47.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$ROOT_DIR/App/KindleWallApp.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

echo "T47 verification passed"
