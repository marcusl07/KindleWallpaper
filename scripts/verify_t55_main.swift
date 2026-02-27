import Foundation

func testDailyRetryRunsAfterInitialBusyRejection() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    defaults.rotationScheduleMode = .daily
    defaults.scheduleDailyHour = 9
    defaults.scheduleDailyMinute = 0

    let calendar = makeUTCCalendar()
    let clock = MutableClock(dateFromUTC(2026, 1, 10, 9, 0, 0))
    var rotateCalls = 0

    let scheduler = WallpaperScheduler(
        userDefaults: defaults,
        rotateWallpaper: {
            rotateCalls += 1
            if rotateCalls == 1 {
                return false
            }
            defaults.lastChangedAt = clock.current
            return true
        },
        now: { clock.current },
        calendar: calendar,
        autoStart: false
    )

    scheduler.checkNow()
    expect(rotateCalls == 1, "Expected first daily attempt to run at scheduled time")

    defaults.lastChangedAt = dateFromUTC(2026, 1, 10, 9, 0, 30)
    clock.current = dateFromUTC(2026, 1, 10, 9, 1, 0)
    scheduler.checkNow()
    expect(
        rotateCalls == 2,
        "Expected pending daily retry to run even when lastChangedAt already crossed today's scheduled time"
    )
    expect(defaults.lastChangedAt == clock.current, "Expected successful retry to persist the accepted rotation time")

    clock.current = dateFromUTC(2026, 1, 10, 9, 5, 0)
    scheduler.checkNow()
    expect(rotateCalls == 2, "Expected no additional same-day rotation after retry succeeds")
}

func runVerifyT55() {
    testDailyRetryRunsAfterInitialBusyRejection()
    print("verify_t55_main passed")
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T55-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fail("Unable to create isolated UserDefaults suite")
    }

    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "__verifySuiteName")
    return defaults
}

private func clearDefaults(_ defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: "__verifySuiteName"), !suiteName.isEmpty else {
        return
    }

    defaults.removePersistentDomain(forName: suiteName)
}

private func makeUTCCalendar() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
    return calendar
}

private func dateFromUTC(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
    var components = DateComponents()
    components.calendar = makeUTCCalendar()
    components.timeZone = TimeZone(secondsFromGMT: 0)
    components.year = year
    components.month = month
    components.day = day
    components.hour = hour
    components.minute = minute
    components.second = second

    guard let date = components.date else {
        fail("Failed to construct UTC date")
    }
    return date
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func fail(_ message: String) -> Never {
    fputs("Assertion failed: \(message)\n", stderr)
    exit(1)
}

private final class MutableClock {
    var current: Date

    init(_ current: Date) {
        self.current = current
    }
}

runVerifyT55()
