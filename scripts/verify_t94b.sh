#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_FILE="$ROOT_DIR/App/SettingsView.swift"

require_pattern() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! rg -q "$pattern" "$file"; then
    echo "Verification failed: missing $description in $file" >&2
    exit 1
  fi
}

require_pattern "$SETTINGS_FILE" 'Section\("About"\)' "About section"
require_pattern "$SETTINGS_FILE" 'Toggle\("Launch at Login",[[:space:]]*isOn:[[:space:]]*launchAtLoginBinding\)' "Launch at Login toggle"
require_pattern "$SETTINGS_FILE" 'Managed by macOS Login Items\.' "macOS Login Items helper copy"
require_pattern "$SETTINGS_FILE" 'launchAtLoginStatusMessage' "launch-at-login status row"
require_pattern "$SETTINGS_FILE" 'appState\.isLaunchAtLoginEnabled' "AppState launch-at-login status source"
require_pattern "$SETTINGS_FILE" 'appState\.launchAtLoginErrorMessage' "AppState launch-at-login error source"
require_pattern "$SETTINGS_FILE" 'appState\.setLaunchAtLoginEnabled\(enabled\)' "AppState launch-at-login setter binding"
require_pattern "$SETTINGS_FILE" 'KindleWall will open automatically when you log in\.' "enabled status message"
require_pattern "$SETTINGS_FILE" 'KindleWall will not open automatically when you log in\.' "disabled status message"

bash "$ROOT_DIR/scripts/verify_t103.sh"

echo "T94-b verification passed"
