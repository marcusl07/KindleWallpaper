#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t103.XXXXXX)"
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

require_pattern "$ROOT_DIR/App/AppState.swift" 'SMAppService\.mainApp' "main app launch-at-login mapping"
require_pattern "$ROOT_DIR/App/AppState.swift" 'SMAppService\.loginItem\(identifier:[[:space:]]*helperBundleIdentifier\)' "DisplayHelper login item mapping"
require_pattern "$ROOT_DIR/App/AppState.swift" 'com\.marcuslo\.KindleWall\.DisplayHelper' "DisplayHelper login item identifier"
require_pattern "$ROOT_DIR/App/AppState.swift" 'setBackgroundDisplayHelperEnabled' "helper login toggle setter"
require_pattern "$ROOT_DIR/App/SettingsView.swift" 'Toggle\("Launch at Login",[[:space:]]*isOn:[[:space:]]*launchAtLoginBinding\)' "main Launch at Login toggle"
require_pattern "$ROOT_DIR/App/SettingsView.swift" 'Toggle\("Keep wallpaper stable in background",[[:space:]]*isOn:[[:space:]]*backgroundDisplayHelperBinding\)' "background helper toggle"
require_pattern "$ROOT_DIR/App/SettingsView.swift" 'backgroundDisplayHelperErrorMessage' "inline helper login error display"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -D TESTING \
  "$ROOT_DIR/scripts/verify_t103_main.swift" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/DebouncedTaskScheduler.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/WallpaperAssignmentStore.swift" \
  "$ROOT_DIR/App/WallpaperSetter.swift" \
  "$ROOT_DIR/App/DisplayIdentityResolver.swift" \
  "$ROOT_DIR/App/WallpaperTopologyRestorer.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/BulkBookDeletionPlan.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  -o "$TMP_DIR/verify_t103_main"

"$TMP_DIR/verify_t103_main"

echo "T103 verification passed"
