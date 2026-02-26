#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t46.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -U -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file" >&2
    exit 1
  fi
}

require_min_count() {
  local file="$1"
  local pattern="$2"
  local minimum="$3"
  local description="$4"

  local count
  count="$(rg -o "$pattern" "$file" | wc -l | tr -d ' ')"
  if [[ "$count" -lt "$minimum" ]]; then
    echo "Verification failed: expected at least $minimum occurrences of $description, found $count" >&2
    exit 1
  fi
}

require_pattern "$APP_STATE_FILE" '@MainActor\s*\nfinal class AppState' "main-actor AppState ownership"
require_pattern "$APP_FILE" '@MainActor\s*\nprivate final class AppDelegate' "main-actor AppDelegate ownership"
require_pattern "$APP_FILE" '@MainActor\s*\nprivate final class SettingsWindowCoordinator' "main-actor settings window coordinator ownership"
require_pattern "$APP_FILE" '@MainActor\s*\nprivate final class StatusItemController' "main-actor status item ownership"
require_pattern "$APP_FILE" 'publishImportStatusOnMain:[[:space:]]+VolumeWatcher\.PublishImportStatus[[:space:]]*=[[:space:]]*\{[[:space:]]+status[[:space:]]+in[[:space:]]+Task[[:space:]]*\{[[:space:]]*@MainActor[[:space:]]+in' "explicit background-to-main import-status hop"
require_min_count "$APP_FILE" 'Task \{ @MainActor' 5 "explicit main-actor hops in app entry/controller surfaces"

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

cp "$ROOT_DIR/scripts/verify_t46_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t46_main"

"$TMP_DIR/verify_t46_main"

echo "T46 verification passed"
