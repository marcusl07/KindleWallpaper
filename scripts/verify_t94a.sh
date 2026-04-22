#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t94a.XXXXXX)"
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

require_pattern "$APP_STATE_FILE" 'SMAppService\.mainApp' "SMAppService main app wiring"
require_pattern "$APP_STATE_FILE" 'var[[:space:]]+isLaunchAtLoginEnabled:[[:space:]]+Bool' "launch-at-login state"
require_pattern "$APP_STATE_FILE" 'var[[:space:]]+launchAtLoginErrorMessage:[[:space:]]+String\?' "launch-at-login error message"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+refreshLaunchAtLoginState\(\)' "launch-at-login refresh API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+setLaunchAtLoginEnabled\(_[[:space:]]+enabled:[[:space:]]+Bool\)' "launch-at-login toggle API"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+toggleLaunchAtLogin\(\)' "launch-at-login toggle helper"
require_pattern "$APP_STATE_FILE" 'LaunchAtLoginService' "launch-at-login service helper"

cp "$ROOT_DIR/scripts/verify_t94a_main.swift" "$TMP_DIR/main.swift"
cp "$ROOT_DIR/scripts/verify_t94a_support.swift" "$TMP_DIR/verify_t94a_support.swift"
cp "$ROOT_DIR/App/AppState.swift" "$TMP_DIR/AppState.swift"
cp "$ROOT_DIR/App/ScheduleSettings.swift" "$TMP_DIR/ScheduleSettings.swift"
cp "$ROOT_DIR/Models/Book.swift" "$TMP_DIR/Book.swift"
cp "$ROOT_DIR/Models/BulkBookDeletionPlan.swift" "$TMP_DIR/BulkBookDeletionPlan.swift"
cp "$ROOT_DIR/Models/Highlight.swift" "$TMP_DIR/Highlight.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$TMP_DIR/main.swift" \
  "$TMP_DIR/verify_t94a_support.swift" \
  "$TMP_DIR/AppState.swift" \
  "$TMP_DIR/ScheduleSettings.swift" \
  "$TMP_DIR/Book.swift" \
  "$TMP_DIR/BulkBookDeletionPlan.swift" \
  "$TMP_DIR/Highlight.swift" \
  -o "$TMP_DIR/verify_t94a_main"

"$TMP_DIR/verify_t94a_main"

echo "T94-a verification passed"
