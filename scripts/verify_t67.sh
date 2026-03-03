#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t67.XXXXXX)"
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

require_pattern "$SETTINGS_FILE" 'private[[:space:]]+func[[:space:]]+settingsNavigationRow\(title:[[:space:]]*String,[[:space:]]*subtitle:[[:space:]]*String\)' "shared navigation row helper"
require_pattern "$SETTINGS_FILE" 'Image\(systemName:[[:space:]]*"chevron\.right"\)' "trailing chevron accessory"
require_pattern "$SETTINGS_FILE" 'NavigationLink\(value:[[:space:]]*SettingsDestination\.books\)' "books navigation row"
require_pattern "$SETTINGS_FILE" 'NavigationLink\(value:[[:space:]]*SettingsDestination\.backgrounds\)' "backgrounds navigation row"
require_pattern "$SETTINGS_FILE" 'title:[[:space:]]*"Manage Books"' "books row title"
require_pattern "$SETTINGS_FILE" 'title:[[:space:]]*"Show Backgrounds"' "backgrounds row title"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

echo "T67 verification passed"
