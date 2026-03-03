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

forbid_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if rg -q "$pattern" "$file"; then
    echo "Verification failed: unexpected $description in $file" >&2
    exit 1
  fi
}

require_pattern "$SETTINGS_FILE" 'List[[:space:]]*\{' "plain root settings list"
require_pattern "$SETTINGS_FILE" 'settingsNavigationButton\(' "explicit settings navigation button helper"
require_pattern "$SETTINGS_FILE" 'destination:[[:space:]]*\.books' "books navigation button destination"
require_pattern "$SETTINGS_FILE" 'destination:[[:space:]]*\.backgrounds' "backgrounds navigation button destination"
require_pattern "$SETTINGS_FILE" 'navigationModel\.path\.append\(destination\)' "explicit path push navigation"
forbid_pattern "$SETTINGS_FILE" 'List\(selection:' "root settings selection binding"
forbid_pattern "$SETTINGS_FILE" 'selectedRootDestination' "root selection state"
forbid_pattern "$SETTINGS_FILE" 'resetRootSelection' "root selection reset helper"
forbid_pattern "$SETTINGS_FILE" '\.tag\(SettingsDestination\.books\)' "books row selection tag"
forbid_pattern "$SETTINGS_FILE" '\.tag\(SettingsDestination\.backgrounds\)' "backgrounds row selection tag"

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
