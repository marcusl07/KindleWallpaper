#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SETTINGS_VIEW_FILE="$ROOT_DIR/App/SettingsView.swift"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t26.XXXXXX)"
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

require_pattern "$SETTINGS_VIEW_FILE" 'Text\("Every interval"\)' "generic interval mode label"
require_pattern "$SETTINGS_VIEW_FILE" 'TextField\(' "interval text field"
require_pattern "$SETTINGS_VIEW_FILE" 'value: scheduleIntervalHoursBinding' "interval hours text entry"
require_pattern "$SETTINGS_VIEW_FILE" 'value: scheduleIntervalMinutesBinding' "interval minutes text entry"

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

let suiteName = "KindleWall-T26-\(UUID().uuidString)"
guard let defaults = UserDefaults(suiteName: suiteName) else {
    fputs("Unable to create UserDefaults suite\n", stderr)
    exit(1)
}

defer {
    defaults.removePersistentDomain(forName: suiteName)
}

assertEqual(defaults.scheduleDailyHour, 9, "Default hour should be 9")
assertEqual(defaults.scheduleDailyMinute, 0, "Default minute should be 0")
assertEqual(defaults.scheduleIntervalMinutes, 30, "Default interval should be 30 minutes")

defaults.scheduleDailyHour = 14
defaults.scheduleDailyMinute = 37
defaults.scheduleIntervalMinutes = 125
assertEqual(defaults.scheduleDailyHour, 14, "Stored hour should persist")
assertEqual(defaults.scheduleDailyMinute, 37, "Stored minute should persist")
assertEqual(defaults.scheduleIntervalMinutes, 125, "Stored interval should persist")

defaults.scheduleDailyHour = -3
defaults.scheduleDailyMinute = 91
defaults.scheduleIntervalMinutes = 0
assertEqual(defaults.scheduleDailyHour, 0, "Hour should clamp low/high bounds")
assertEqual(defaults.scheduleDailyMinute, 59, "Minute should clamp low/high bounds")
assertEqual(defaults.scheduleIntervalMinutes, 1, "Interval should clamp to the minimum")

defaults.scheduleIntervalMinutes = 2_000
assertEqual(defaults.scheduleIntervalMinutes, 1_439, "Interval should clamp to the maximum")

defaults.removeObject(forKey: "scheduleDailyHour")
defaults.removeObject(forKey: "scheduleDailyMinute")
defaults.removeObject(forKey: "scheduleIntervalMinutes")
assertEqual(defaults.scheduleDailyHour, 9, "Missing hour should use default")
assertEqual(defaults.scheduleDailyMinute, 0, "Missing minute should use default")
assertEqual(defaults.scheduleIntervalMinutes, 30, "Missing interval should use default")

defaults.set("every30Minutes", forKey: "rotationScheduleMode")
assertEqual(defaults.rotationScheduleMode, .everyInterval, "Legacy string mode should migrate to everyInterval")

defaults.set(NSNumber(value: 3), forKey: "rotationScheduleMode")
assertEqual(defaults.rotationScheduleMode, .everyInterval, "Legacy index mode should migrate to everyInterval")

defaults.rotationScheduleMode = .everyInterval
assertEqual(defaults.string(forKey: "rotationScheduleMode"), "everyInterval", "New mode should persist using the generic value")

print("T26 verification passed")
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/t26_runner"

"$TMP_DIR/t26_runner"
