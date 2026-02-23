#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"

require_pattern() {
  local pattern="$1"
  local description="$2"

  if ! rg -q "$pattern" "$SETTINGS_FILE"; then
    echo "Verification failed: missing $description in App/SettingsView.swift" >&2
    exit 1
  fi
}

forbid_pattern() {
  local pattern="$1"
  local description="$2"

  if rg -q "$pattern" "$SETTINGS_FILE"; then
    echo "Verification failed: found unexpected $description in App/SettingsView.swift" >&2
    exit 1
  fi
}

# Route-based settings/books view split.
require_pattern "private[[:space:]]+enum[[:space:]]+SettingsRoute" "SettingsRoute enum"
require_pattern "case[[:space:]]+main" "main route case"
require_pattern "case[[:space:]]+books" "books route case"
require_pattern "switch[[:space:]]+route" "route switch in body"
require_pattern "private[[:space:]]+var[[:space:]]+booksManagementContent:[[:space:]]+some[[:space:]]+View" "dedicated books management view"

# Main settings uses button entrypoint instead of inline list.
require_pattern "Button\(\"Show Books\.\.\.\"\)" "Show Books button"

# Books management view controls.
require_pattern "Button\(\"Back\"\)" "Back button"
require_pattern "Button\(\"Select All\"\)" "Select All control"
require_pattern "Button\(\"Deselect All\"\)" "Deselect All control"
require_pattern "List[[:space:]]*\{" "books list"
require_pattern "\.frame\(maxWidth:[[:space:]]*\.infinity,[[:space:]]*maxHeight:[[:space:]]*\.infinity\)" "full-height books list frame"

# Legacy nested-scroll workaround and inline-height-constrained list should be gone.
forbid_pattern "isHoveringBooksList" "hover-based nested scroll workaround"
forbid_pattern "booksListHeight" "fixed inline books list height constant"
forbid_pattern "\.scrollDisabled\(" "parent scroll disable workaround"

swiftc -frontend -parse "$SETTINGS_FILE"

echo "T55 verification passed"
