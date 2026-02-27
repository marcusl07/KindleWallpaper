#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"

require_pattern() {
  local pattern="$1"
  local description="$2"

  if ! rg -q "$pattern" "$APP_FILE"; then
    echo "Verification failed: missing $description in App/KindleWallApp.swift" >&2
    exit 1
  fi
}

# Coordinator should observe app deactivation and restore window visibility when needed.
require_pattern "private[[:space:]]+var[[:space:]]+appDidResignActiveObserver:[[:space:]]+NSObjectProtocol\\?" "app deactivation observer storage"
require_pattern "installAppDeactivationObserver\\(\\)" "deactivation observer installation"
require_pattern "NSApplication\\.didResignActiveNotification" "did-resign-active observer registration"
require_pattern "private[[:space:]]+func[[:space:]]+restoreWindowVisibilityAfterAppDeactivation\\(\\)" "deactivation restore method"
require_pattern "restoreVisibilityIfNeeded\\(for:[[:space:]]+settingsWindowController\\?\\.window\\)" "settings window restore path"
require_pattern "guard[[:space:]]+!window\\.isVisible[[:space:]]+else" "restore guard for already-visible windows"
require_pattern "guard[[:space:]]+!window\\.isMiniaturized[[:space:]]+else" "restore guard for miniaturized windows"
require_pattern "window\\.orderFront\\(nil\\)" "window re-show on deactivation path"

# Explicit close semantics must remain intact.
require_pattern "func[[:space:]]+windowWillClose\\(_[[:space:]]+notification:[[:space:]]+Notification\\)" "window close delegate"
require_pattern "settingsWindowController[[:space:]]*=[[:space:]]*nil" "settings teardown on explicit close"

TMP_DIR="$(mktemp -d /tmp/kindlewall_t41.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  -typecheck \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/App/AppSupportPaths.swift" \
  "$ROOT_DIR/App/BackgroundImageStore.swift" \
  "$ROOT_DIR/App/BackgroundImageLoader.swift" \
  "$ROOT_DIR/App/SettingsView.swift" \
  "$ROOT_DIR/App/MenuBarView.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$ROOT_DIR/App/KindleWallApp.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$ROOT_DIR/Models/Highlight.swift"

echo "T41 verification passed"
