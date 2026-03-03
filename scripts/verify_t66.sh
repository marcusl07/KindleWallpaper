#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
STORE_FILE="$ROOT_DIR/App/BackgroundImageStore.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t66.XXXXXX)"
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

require_pattern "$STORE_FILE" 'let[[:space:]]+selectedItemID:[[:space:]]+UUID\?' "selected collection item identity"
require_pattern "$STORE_FILE" 'static[[:space:]]+let[[:space:]]+selectedBackgroundImageID' "persisted selected background key"
require_pattern "$STORE_FILE" 'let[[:space:]]+sortOrder:[[:space:]]+Int\?' "stable collection sort order metadata"
require_pattern "$STORE_FILE" 'func[[:space:]]+stableSortedRecords\(_[[:space:]]+records:[[:space:]]*\[ManifestRecord\]\)' "stable collection sort helper"
require_pattern "$APP_STATE_FILE" 'selectedItemID:[[:space:]]+UUID\?' "app state selected background boundary"
require_pattern "$SETTINGS_FILE" 'selectedBackgroundID[[:space:]]*=[[:space:]]*collectionState\.selectedItemID' "view selection sourced from explicit selected id"

cp "$ROOT_DIR/scripts/verify_t57_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t66_main"

"$TMP_DIR/verify_t66_main"

echo "T66 verification passed"
