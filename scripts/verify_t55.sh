#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEDULER_FILE="$ROOT_DIR/App/WallpaperScheduler.swift"
APP_STATE_FILE="$ROOT_DIR/App/AppState.swift"
APP_FILE="$ROOT_DIR/App/KindleWallApp.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t55.XXXXXX)"
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

require_pattern "$SCHEDULER_FILE" 'pendingDailyScheduledTime' "pending daily retry state"
require_pattern "$SCHEDULER_FILE" 'private[[:space:]]+func[[:space:]]+evaluateDailySchedule\(\)' "daily evaluation helper"
require_pattern "$APP_STATE_FILE" 'func[[:space:]]+requestWallpaperRotationSynchronously\([[:space:]]*forcedHighlight:[[:space:]]*Highlight\?[[:space:]]*=[[:space:]]*nil[[:space:]]*\)[[:space:]]*->[[:space:]]*Bool' "synchronous rotation request bridge"
require_pattern "$APP_FILE" 'requestWallpaperRotationSynchronously\(\)' "scheduler wiring using synchronous rotation request"

cp "$ROOT_DIR/scripts/verify_t55_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/verify_t55_main"

"$TMP_DIR/verify_t55_main"

echo "T55 verification passed"
