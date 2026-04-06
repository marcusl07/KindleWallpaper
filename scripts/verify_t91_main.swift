import Foundation

func testOnLaunchModeStillRotatesImmediately() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    defaults.rotationScheduleMode = .onLaunch
    let clock = MutableClock(dateFromUTC(2026, 4, 6, 9, 30, 0))
    let timerFactory = TimerFactory()
    var rotateCalls = 0

    let scheduler = WallpaperScheduler(
        userDefaults: defaults,
        rotateWallpaper: {
            rotateCalls += 1
            defaults.lastChangedAt = clock.current
            return true
        },
        now: { clock.current },
        calendar: makeUTCCalendar(),
        repeatingTimerFactory: timerFactory.make(interval:handler:)
    )

    expect(rotateCalls == 1, "Expected on-launch mode to rotate during startup")

    timerFactory.fireAll()
    expect(rotateCalls == 1, "Expected on-launch mode to avoid timer-driven startup follow-up")

    scheduler.stop()
}

func testDailyModeSkipsMissedStartupRunUntilTomorrow() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    defaults.rotationScheduleMode = .daily
    defaults.scheduleDailyHour = 9
    defaults.scheduleDailyMinute = 0

    let clock = MutableClock(dateFromUTC(2026, 4, 6, 9, 30, 0))
    let timerFactory = TimerFactory()
    var rotateCalls = 0

    let scheduler = WallpaperScheduler(
        userDefaults: defaults,
        rotateWallpaper: {
            rotateCalls += 1
            defaults.lastChangedAt = clock.current
            return true
        },
        now: { clock.current },
        calendar: makeUTCCalendar(),
        repeatingTimerFactory: timerFactory.make(interval:handler:)
    )

    expect(rotateCalls == 0, "Expected daily mode to skip missed startup run")

    clock.current = dateFromUTC(2026, 4, 6, 12, 0, 0)
    timerFactory.fireAll()
    expect(rotateCalls == 0, "Expected daily mode to keep skipping the missed same-day startup run")

    clock.current = dateFromUTC(2026, 4, 7, 8, 59, 0)
    timerFactory.fireAll()
    expect(rotateCalls == 0, "Expected daily mode not to rotate before the next day's scheduled time")

    clock.current = dateFromUTC(2026, 4, 7, 9, 0, 0)
    timerFactory.fireAll()
    expect(rotateCalls == 1, "Expected daily mode to rotate at the next scheduled occurrence")

    scheduler.stop()
}

func testDailyModeLaunchAtExactScheduledTimeAlsoWaitsForNextOccurrence() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    defaults.rotationScheduleMode = .daily
    defaults.scheduleDailyHour = 9
    defaults.scheduleDailyMinute = 0

    let clock = MutableClock(dateFromUTC(2026, 4, 6, 9, 0, 0))
    let timerFactory = TimerFactory()
    var rotateCalls = 0

    let scheduler = WallpaperScheduler(
        userDefaults: defaults,
        rotateWallpaper: {
            rotateCalls += 1
            defaults.lastChangedAt = clock.current
            return true
        },
        now: { clock.current },
        calendar: makeUTCCalendar(),
        repeatingTimerFactory: timerFactory.make(interval:handler:)
    )

    expect(rotateCalls == 0, "Expected daily mode to avoid startup rotation even at the scheduled minute")

    clock.current = dateFromUTC(2026, 4, 7, 9, 0, 0)
    timerFactory.fireAll()
    expect(rotateCalls == 1, "Expected daily mode to wait until the next day's scheduled occurrence")

    scheduler.stop()
}

func testEveryIntervalModeSkipsStartupAndWaitsForStoredIntervalFromLaunch() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    defaults.rotationScheduleMode = .everyInterval
    defaults.scheduleIntervalMinutes = 45
    let clock = MutableClock(dateFromUTC(2026, 4, 6, 10, 0, 0))
    defaults.lastChangedAt = clock.current.addingTimeInterval(-(60 * 60))

    let timerFactory = TimerFactory()
    var rotateCalls = 0

    let scheduler = WallpaperScheduler(
        userDefaults: defaults,
        rotateWallpaper: {
            rotateCalls += 1
            defaults.lastChangedAt = clock.current
            return true
        },
        now: { clock.current },
        calendar: makeUTCCalendar(),
        repeatingTimerFactory: timerFactory.make(interval:handler:)
    )

    expect(rotateCalls == 0, "Expected interval mode to skip startup catch-up rotation")

    clock.current = dateFromUTC(2026, 4, 6, 10, 44, 0)
    timerFactory.fireAll()
    expect(rotateCalls == 0, "Expected interval mode to wait the full stored interval after launch")

    clock.current = dateFromUTC(2026, 4, 6, 10, 45, 0)
    timerFactory.fireAll()
    expect(rotateCalls == 1, "Expected interval mode to rotate after the stored post-launch delay")

    scheduler.stop()
}

func testEveryIntervalDeferredLaunchRespectsRecentManualRotation() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    defaults.rotationScheduleMode = .everyInterval
    defaults.scheduleIntervalMinutes = 45
    let clock = MutableClock(dateFromUTC(2026, 4, 6, 10, 0, 0))
    defaults.lastChangedAt = clock.current.addingTimeInterval(-(60 * 60))

    let timerFactory = TimerFactory()
    var rotateCalls = 0

    let scheduler = WallpaperScheduler(
        userDefaults: defaults,
        rotateWallpaper: {
            rotateCalls += 1
            defaults.lastChangedAt = clock.current
            return true
        },
        now: { clock.current },
        calendar: makeUTCCalendar(),
        repeatingTimerFactory: timerFactory.make(interval:handler:)
    )

    expect(rotateCalls == 0, "Expected interval mode to defer startup rotation")

    clock.current = dateFromUTC(2026, 4, 6, 10, 20, 0)
    defaults.lastChangedAt = clock.current

    clock.current = dateFromUTC(2026, 4, 6, 10, 45, 0)
    timerFactory.fireAll()
    expect(rotateCalls == 0, "Expected deferred launch check to honor a newer manual rotation")

    clock.current = dateFromUTC(2026, 4, 6, 11, 5, 0)
    timerFactory.fireAll()
    expect(rotateCalls == 1, "Expected interval mode to resume from the newer rotation time")

    scheduler.stop()
}

func runVerifyT91() {
    testOnLaunchModeStillRotatesImmediately()
    testDailyModeSkipsMissedStartupRunUntilTomorrow()
    testDailyModeLaunchAtExactScheduledTimeAlsoWaitsForNextOccurrence()
    testEveryIntervalModeSkipsStartupAndWaitsForStoredIntervalFromLaunch()
    testEveryIntervalDeferredLaunchRespectsRecentManualRotation()
    print("verify_t91_main passed")
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T91-\(UUID().uuidString)"
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

private final class FakeRepeatingTimer: WallpaperSchedulerTimer {
    private var handler: (() -> Void)?

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func fire() {
        handler?()
    }

    func invalidate() {
        handler = nil
    }
}

private final class TimerFactory {
    private(set) var timers: [FakeRepeatingTimer] = []

    func make(interval: TimeInterval, handler: @escaping () -> Void) -> WallpaperSchedulerTimer {
        let timer = FakeRepeatingTimer(handler: handler)
        timers.append(timer)
        return timer
    }

    func fireAll() {
        for timer in timers {
            timer.fire()
        }
    }
}

runVerifyT91()
