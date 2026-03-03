#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t68.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'List\(selection:[[:space:]]*\$navigationModel\.selectedRootDestination\)' "root settings list selection binding"
require_pattern "$SETTINGS_FILE" 'navigationModel\.resetRootSelection\(\)' "root selection reset on appear"
require_pattern "$SETTINGS_FILE" 'NavigationLink\(value:[[:space:]]*SettingsDestination\.books\)' "books navigation link"
require_pattern "$SETTINGS_FILE" 'NavigationLink\(value:[[:space:]]*SettingsDestination\.backgrounds\)' "backgrounds navigation link"
require_pattern "$SETTINGS_FILE" '\.tag\(SettingsDestination\.books\)' "books row selection tag"
require_pattern "$SETTINGS_FILE" '\.tag\(SettingsDestination\.backgrounds\)' "backgrounds row selection tag"

cp "$ROOT_DIR/scripts/verify_t68_main.swift" "$TMP_DIR/main.swift"

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
  -o "$TMP_DIR/verify_t68_main"

"$TMP_DIR/verify_t68_main"

echo "T68 verification passed"
