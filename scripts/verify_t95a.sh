#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
PROJECT_FILE="$ROOT_DIR/project.yml"
APP_INFO_FILE="$ROOT_DIR/App/Info.plist"
HELPER_INFO_FILE="$ROOT_DIR/DisplayHelper/Info.plist"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file" >&2
    exit 1
  fi
}

require_pattern "$APP_STATE_FILE" 'SMAppService\.mainApp' "main app launch-at-login ServiceManagement mapping"
require_pattern "$APP_STATE_FILE" 'try service\.register\(\)' "launch-at-login enable registration"
require_pattern "$APP_STATE_FILE" 'try service\.unregister\(\)' "launch-at-login disable registration"
require_pattern "$APP_STATE_FILE" 'SMAppService\.loginItem\(identifier:[[:space:]]*helperBundleIdentifier\)' "DisplayHelper login-item ServiceManagement mapping"
require_pattern "$APP_STATE_FILE" 'com\.marcuslo\.KindleWall\.DisplayHelper' "DisplayHelper login-item bundle identifier"
require_pattern "$APP_FILE" 'reapplyCurrentWallpaperForTopologyChange' "startup/accessory-app wallpaper restore path"
require_pattern "$PROJECT_FILE" 'Embed DisplayHelper Login Item' "bundled login-item embed phase"
require_pattern "$APP_INFO_FILE" '<key>LSUIElement</key>' "main app accessory LSUIElement key"
require_pattern "$HELPER_INFO_FILE" '<key>LSUIElement</key>' "DisplayHelper accessory LSUIElement key"

bash "$ROOT_DIR/scripts/verify_t94a.sh"
bash "$ROOT_DIR/scripts/verify_t94b.sh"
bash "$ROOT_DIR/scripts/verify_t61.sh"
bash "$ROOT_DIR/scripts/verify_t91.sh"
bash "$ROOT_DIR/scripts/verify_t103.sh"

echo "T95-a verification passed"
