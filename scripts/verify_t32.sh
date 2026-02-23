#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t32.XXXXXX)"
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
    echo "Verification failed: found forbidden $description in $file" >&2
    exit 1
  fi
}

require_pattern "$SETTINGS_FILE" 'sectionContainer\(title:[[:space:]]*"Books"\)' "Books section container"
require_pattern "$SETTINGS_FILE" 'Button\("Select All"\)' "Select All button"
require_pattern "$SETTINGS_FILE" 'Button\("Deselect All"\)' "Deselect All button"
require_pattern "$SETTINGS_FILE" 'appState\.setAllBooksEnabled\(true\)' "Select All action"
require_pattern "$SETTINGS_FILE" 'appState\.setAllBooksEnabled\(false\)' "Deselect All action"
require_pattern "$SETTINGS_FILE" 'List[[:space:]]*\{' "books list rendering"
require_pattern "$SETTINGS_FILE" 'ForEach\(appState\.books\)' "book list rendering"
require_pattern "$SETTINGS_FILE" 'Toggle\(isOn:[[:space:]]*bindingForBook\(book\)\)' "per-book checkbox toggle"
require_pattern "$SETTINGS_FILE" '\.toggleStyle\(\.checkbox\)' "checkbox style"
require_pattern "$SETTINGS_FILE" 'appState\.setBookEnabled\(id:[[:space:]]*book\.id,[[:space:]]*enabled:[[:space:]]*enabled\)' "book toggle persistence"
require_pattern "$SETTINGS_FILE" 'allBooksDeselectedWarningVisible' "all-books-deselected warning gate"
forbid_pattern "$SETTINGS_FILE" 'LazyVStack' "LazyVStack in books section"
require_pattern "$APP_STATE_FILE" 'performBookMutation' "centralized AppState book mutation helper"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

cp "$ROOT_DIR/scripts/verify_t32_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t32_main"

"$TMP_DIR/verify_t32_main"

echo "T32 verification passed"
