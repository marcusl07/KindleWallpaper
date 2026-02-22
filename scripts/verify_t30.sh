#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"

require_pattern() {
  local pattern="$1"
  local description="$2"
  local file="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in ${file#$ROOT_DIR/}" >&2
    exit 1
  fi
}

require_pattern "struct[[:space:]]+SettingsView:[[:space:]]*View" "SettingsView declaration" "$SETTINGS_FILE"
require_pattern "@EnvironmentObject[[:space:]]+private[[:space:]]+var[[:space:]]+appState:[[:space:]]+AppState" "AppState environment object wiring" "$SETTINGS_FILE"
require_pattern "sectionContainer\\(title:[[:space:]]*\"Import\"\\)" "Import section" "$SETTINGS_FILE"
require_pattern "sectionContainer\\(title:[[:space:]]*\"Books\"\\)" "Books section" "$SETTINGS_FILE"
require_pattern "sectionContainer\\(title:[[:space:]]*\"Background Image\"\\)" "Background Image section" "$SETTINGS_FILE"
require_pattern "sectionContainer\\(title:[[:space:]]*\"Rotation Schedule\"\\)" "Rotation Schedule section" "$SETTINGS_FILE"
require_pattern "sectionContainer\\(title:[[:space:]]*\"About\"\\)" "About section" "$SETTINGS_FILE"
require_pattern "SettingsView\\(\\)" "Settings scene using SettingsView" "$APP_FILE"

TMP_DIR="$(mktemp -d /tmp/kindlewall_t30.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

echo "T30 verification passed"
