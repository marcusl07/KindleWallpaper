#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCHEDULER_FILE="$ROOT_DIR/App/WallpaperScheduler.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t91.XXXXXX)"
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

require_pattern "$SCHEDULER_FILE" 'deferredDailyCheckUntil' "deferred daily startup state"
require_pattern "$SCHEDULER_FILE" 'deferredIntervalCheckUntil' "deferred interval startup state"
require_pattern "$SCHEDULER_FILE" 'shouldRotateEveryInterval' "interval threshold helper"
require_pattern "$SCHEDULER_FILE" 'nextScheduledTime' "next scheduled-time helper"

cp "$ROOT_DIR/scripts/verify_t91_main.swift" "$TMP_DIR/main.swift"

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/verify_t91_main"

"$TMP_DIR/verify_t91_main"

echo "T91 verification passed"
