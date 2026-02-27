#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t33.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

require_pattern() {
  local pattern="$1"
  local description="$2"

  if ! rg -q "$pattern" "$SETTINGS_FILE"; then
    echo "Verification failed: missing $description in App/SettingsView.swift" >&2
    exit 1
  fi
}

require_pattern 'sectionContainer\(title:[[:space:]]*"Background Image"\)' "Background Image section container"
require_pattern 'Text\("No image — black background"\)' "no-image placeholder label"
require_pattern 'Button\("Change Image\.\.\."\)' "Change Image button"
require_pattern 'NSOpenPanel\(\)' "NSOpenPanel picker"
require_pattern 'allowedContentTypes[[:space:]]*=[[:space:]]*\[\.jpeg,[[:space:]]*\.png,[[:space:]]*\.heic\]' "image type filter"
require_pattern 'saveBackgroundImageSelection\(from:' "background image persistence call"
require_pattern 'refreshBackgroundThumbnail\(\)' "thumbnail refresh call"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

echo "T33 verification passed"
