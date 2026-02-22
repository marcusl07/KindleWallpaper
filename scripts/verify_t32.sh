#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t32.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

require_pattern() {
  local pattern="$1"
  local description="$2"

  if ! rg -q "$pattern" "$SETTINGS_FILE"; then
    echo "Verification failed: missing $description in App/SettingsView.swift" >&2
    exit 1
  fi
}

require_pattern 'sectionContainer\(title:[[:space:]]*"Books"\)' "Books section container"
require_pattern 'Button\("Select All"\)' "Select All button"
require_pattern 'Button\("Deselect All"\)' "Deselect All button"
require_pattern 'appState\.setAllBooksEnabled\(true\)' "Select All action"
require_pattern 'appState\.setAllBooksEnabled\(false\)' "Deselect All action"
require_pattern 'ForEach\(appState\.books\)' "book list rendering"
require_pattern 'Toggle\(isOn:[[:space:]]*bindingForBook\(book\)\)' "per-book checkbox toggle"
require_pattern '\.toggleStyle\(\.checkbox\)' "checkbox style"
require_pattern 'appState\.setBookEnabled\(id:[[:space:]]*book\.id,[[:space:]]*enabled:[[:space:]]*enabled\)' "book toggle persistence"
require_pattern 'allBooksDeselectedWarningVisible' "all-books-deselected warning gate"

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
