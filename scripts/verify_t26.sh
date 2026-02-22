#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t26.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

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

defaults.scheduleDailyHour = 14
defaults.scheduleDailyMinute = 37
assertEqual(defaults.scheduleDailyHour, 14, "Stored hour should persist")
assertEqual(defaults.scheduleDailyMinute, 37, "Stored minute should persist")

defaults.scheduleDailyHour = -3
defaults.scheduleDailyMinute = 91
assertEqual(defaults.scheduleDailyHour, 0, "Hour should clamp low/high bounds")
assertEqual(defaults.scheduleDailyMinute, 59, "Minute should clamp low/high bounds")

defaults.removeObject(forKey: "scheduleDailyHour")
defaults.removeObject(forKey: "scheduleDailyMinute")
assertEqual(defaults.scheduleDailyHour, 9, "Missing hour should use default")
assertEqual(defaults.scheduleDailyMinute, 0, "Missing minute should use default")

print("T26 verification passed")
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/t26_runner"

"$TMP_DIR/t26_runner"
