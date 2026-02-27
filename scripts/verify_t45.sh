#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t45.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" '@Published[[:space:]]+private\(set\)[[:space:]]+var[[:space:]]+isBookMutationInFlight:[[:space:]]+Bool' "book mutation in-flight published state"
require_pattern "$APP_STATE_FILE" 'isBookMutationInFlight[[:space:]]*=[[:space:]]*true' "in-flight state set true at mutation start"
require_pattern "$APP_STATE_FILE" 'isBookMutationInFlight[[:space:]]*=[[:space:]]*false' "in-flight state reset after mutation"
require_pattern "$SETTINGS_FILE" 'appState\.isBookMutationInFlight' "books controls disabled while mutation in-flight"
require_pattern "$SETTINGS_FILE" '\.disabled\(appState\.isBookMutationInFlight\)' "book row checkbox disable during mutation"

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

cp "$ROOT_DIR/scripts/verify_t45_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$TMP_DIR/main.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t45_main"

"$TMP_DIR/verify_t45_main"

echo "T45 verification passed"
