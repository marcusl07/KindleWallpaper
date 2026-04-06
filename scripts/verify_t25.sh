#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t25.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/verify_t25.swift" <<'SWIFT'
import Foundation

@main
struct VerifyT25 {
    static func main() {
        testRotationScheduleModeDefaultsToDaily()
        testOnLaunchRotatesExactlyOnceAtStartup()
        testManualModeNeverRotates()
        testEveryThirtyMinutesSkipsStartupCatchUpAndRequiresPostLaunchThreshold()
        testDailyModeRotatesOnceAfterScheduledTimePerDay()
        testDailyModeSkipsWhenLastChangedAtIsAtOrAfterScheduledTime()
        testSchedulerStartStopAreIdempotentAndUseSixtySecondTimer()
        testSchedulerReentrancyGuardPreventsNestedRotation()
        print("T25 verification passed")
    }

    private static func testRotationScheduleModeDefaultsToDaily() {
        let defaults = makeDefaults()
        defer { clearDefaults(defaults) }

        expect(defaults.rotationScheduleMode == .daily, "Expected schedule mode default to be daily")
    }

    private static func testOnLaunchRotatesExactlyOnceAtStartup() {
        let defaults = makeDefaults()
        defer { clearDefaults(defaults) }

        defaults.rotationScheduleMode = .onLaunch
        let clock = MutableClock(dateFromUTC(2026, 1, 10, 9, 0, 0))
        let timerFactory = TimerFactory()
        var rotateCallCount = 0

        let scheduler = WallpaperScheduler(
            userDefaults: defaults,
            rotateWallpaper: {
                rotateCallCount += 1
                defaults.lastChangedAt = clock.current
                return true
            },
            now: { clock.current },
            calendar: makeUTCCalendar(),
            repeatingTimerFactory: timerFactory.make(interval:handler:)
        )

        expect(rotateCallCount == 1, "Expected on-launch mode to rotate exactly once on startup")
        expect(defaults.lastChangedAt == clock.current, "Expected startup rotation to persist lastChangedAt")
        expect(timerFactory.intervals == [60], "Expected repeating timer interval to be 60 seconds")

        timerFactory.fireAll()
        expect(rotateCallCount == 1, "Expected timer ticks to not re-rotate while in on-launch mode")

        scheduler.stop()
    }

    private static func testManualModeNeverRotates() {
        let defaults = makeDefaults()
        defer { clearDefaults(defaults) }

        defaults.rotationScheduleMode = .manual
        let timerFactory = TimerFactory()
        var rotateCallCount = 0

        let scheduler = WallpaperScheduler(
            userDefaults: defaults,
            rotateWallpaper: {
                rotateCallCount += 1
                return true
            },
            repeatingTimerFactory: timerFactory.make(interval:handler:)
        )

        expect(rotateCallCount == 0, "Expected manual mode to skip startup rotation")
        timerFactory.fireAll()
        expect(rotateCallCount == 0, "Expected manual mode to skip timer-based rotation")

        scheduler.stop()
    }

    private static func testEveryThirtyMinutesSkipsStartupCatchUpAndRequiresPostLaunchThreshold() {
        let defaults = makeDefaults()
        defer { clearDefaults(defaults) }

        defaults.rotationScheduleMode = .everyInterval
        let clock = MutableClock(dateFromUTC(2026, 1, 10, 10, 0, 0))
        defaults.lastChangedAt = clock.current.addingTimeInterval(-1_801)

        let timerFactory = TimerFactory()
        var rotateCallCount = 0

        let scheduler = WallpaperScheduler(
            userDefaults: defaults,
            rotateWallpaper: {
                rotateCallCount += 1
                defaults.lastChangedAt = clock.current
                return true
            },
            now: { clock.current },
            calendar: makeUTCCalendar(),
            repeatingTimerFactory: timerFactory.make(interval:handler:)
        )

        expect(rotateCallCount == 0, "Expected every-30 mode to skip missed startup catch-up rotation")

        clock.current = clock.current.addingTimeInterval(1)
        timerFactory.fireAll()
        expect(rotateCallCount == 0, "Expected every-30 mode to keep waiting after startup")

        clock.current = dateFromUTC(2026, 1, 10, 10, 29, 0)
        timerFactory.fireAll()
        expect(rotateCallCount == 0, "Expected every-30 mode not to rotate before 30 minutes from launch")

        clock.current = dateFromUTC(2026, 1, 10, 10, 30, 0)
        timerFactory.fireAll()
        expect(rotateCallCount == 1, "Expected rotation 30 minutes after launch")

        clock.current = clock.current.addingTimeInterval(120)
        timerFactory.fireAll()
        expect(rotateCallCount == 1, "Expected no extra rotation before another 30 minutes elapse")

        defaults.lastChangedAt = clock.current.addingTimeInterval(300)
        timerFactory.fireAll()
        expect(rotateCallCount == 1, "Expected future lastChangedAt to suppress rotation")

        scheduler.stop()
    }

    private static func testDailyModeRotatesOnceAfterScheduledTimePerDay() {
        let defaults = makeDefaults()
        defer { clearDefaults(defaults) }

        defaults.rotationScheduleMode = .daily
        defaults.scheduleDailyHour = 9
        defaults.scheduleDailyMinute = 0

        let clock = MutableClock(dateFromUTC(2026, 1, 10, 8, 59, 0))
        let timerFactory = TimerFactory()
        var rotateCallCount = 0

        let scheduler = WallpaperScheduler(
            userDefaults: defaults,
            rotateWallpaper: {
                rotateCallCount += 1
                defaults.lastChangedAt = clock.current
                return true
            },
            now: { clock.current },
            calendar: makeUTCCalendar(),
            repeatingTimerFactory: timerFactory.make(interval:handler:)
        )

        expect(rotateCallCount == 0, "Expected daily mode not to rotate before scheduled time")

        clock.current = dateFromUTC(2026, 1, 10, 9, 0, 0)
        timerFactory.fireAll()
        expect(rotateCallCount == 1, "Expected daily mode to rotate at scheduled time")

        clock.current = dateFromUTC(2026, 1, 10, 12, 0, 0)
        timerFactory.fireAll()
        expect(rotateCallCount == 1, "Expected daily mode to avoid second same-day rotation")

        clock.current = dateFromUTC(2026, 1, 11, 9, 0, 0)
        timerFactory.fireAll()
        expect(rotateCallCount == 2, "Expected daily mode to rotate again the next day")

        scheduler.stop()
    }

    private static func testDailyModeSkipsWhenLastChangedAtIsAtOrAfterScheduledTime() {
        let calendar = makeUTCCalendar()
        let now = dateFromUTC(2026, 2, 3, 10, 0, 0)
        let scheduled = dateFromUTC(2026, 2, 3, 9, 0, 0)

        expect(
            WallpaperScheduler.shouldRotateDaily(
                now: now,
                lastChangedAt: scheduled,
                scheduleHour: 9,
                scheduleMinute: 0,
                calendar: calendar
            ) == false,
            "Expected daily mode to skip when lastChangedAt equals today's scheduled time"
        )

        expect(
            WallpaperScheduler.shouldRotateDaily(
                now: now,
                lastChangedAt: scheduled.addingTimeInterval(10),
                scheduleHour: 9,
                scheduleMinute: 0,
                calendar: calendar
            ) == false,
            "Expected daily mode to skip when lastChangedAt is after today's scheduled time"
        )
    }

    private static func testSchedulerStartStopAreIdempotentAndUseSixtySecondTimer() {
        let defaults = makeDefaults()
        defer { clearDefaults(defaults) }

        defaults.rotationScheduleMode = .manual
        let timerFactory = TimerFactory()
        var rotateCallCount = 0

        let scheduler = WallpaperScheduler(
            userDefaults: defaults,
            rotateWallpaper: {
                rotateCallCount += 1
                return true
            },
            repeatingTimerFactory: timerFactory.make(interval:handler:),
            autoStart: false
        )

        scheduler.start()
        scheduler.start()
        expect(timerFactory.timers.count == 1, "Expected start() to be idempotent while running")
        expect(timerFactory.intervals == [60], "Expected scheduler to create a 60-second repeating timer")

        scheduler.stop()
        scheduler.stop()
        expect(timerFactory.timers[0].invalidateCount == 1, "Expected stop() to invalidate timer exactly once")

        timerFactory.timers[0].fire()
        expect(rotateCallCount == 0, "Expected invalidated timer not to trigger rotations")

        scheduler.start()
        expect(timerFactory.timers.count == 2, "Expected scheduler to recreate timer after stop/start")

        scheduler.stop()
    }

    private static func testSchedulerReentrancyGuardPreventsNestedRotation() {
        let defaults = makeDefaults()
        defer { clearDefaults(defaults) }

        defaults.rotationScheduleMode = .everyInterval
        defaults.lastChangedAt = nil
        let timerFactory = TimerFactory()
        var rotateCallCount = 0
        var scheduler: WallpaperScheduler?

        scheduler = WallpaperScheduler(
            userDefaults: defaults,
            rotateWallpaper: {
                rotateCallCount += 1
                defaults.lastChangedAt = Date()
                scheduler?.checkNow()
                return true
            },
            repeatingTimerFactory: timerFactory.make(interval:handler:),
            autoStart: false
        )

        scheduler?.checkNow()
        expect(rotateCallCount == 1, "Expected nested schedule check to be ignored while rotation is in progress")

        scheduler?.stop()
    }

    private static func makeDefaults() -> UserDefaults {
        let suiteName = "KindleWall-T25-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fail("Unable to create isolated UserDefaults suite")
        }

        defaults.removePersistentDomain(forName: suiteName)
        defaults.set(suiteName, forKey: "__verifySuiteName")
        return defaults
    }

    private static func clearDefaults(_ defaults: UserDefaults) {
        guard let suiteName = defaults.string(forKey: "__verifySuiteName"), !suiteName.isEmpty else {
            return
        }

        defaults.removePersistentDomain(forName: suiteName)
    }

    private static func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        return calendar
    }

    private static func dateFromUTC(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
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
            fail("Failed to create UTC date for test fixture")
        }
        return date
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private final class MutableClock {
    var current: Date

    init(_ current: Date) {
        self.current = current
    }
}

private final class FakeRepeatingTimer: WallpaperSchedulerTimer {
    private var handler: (() -> Void)?
    private(set) var invalidateCount = 0

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    func fire() {
        handler?()
    }

    func invalidate() {
        invalidateCount += 1
        handler = nil
    }
}

private final class TimerFactory {
    private(set) var intervals: [TimeInterval] = []
    private(set) var timers: [FakeRepeatingTimer] = []

    func make(interval: TimeInterval, handler: @escaping () -> Void) -> WallpaperSchedulerTimer {
        intervals.append(interval)
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
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/WallpaperScheduler.swift" \
  "$TMP_DIR/verify_t25.swift" \
  -o "$TMP_DIR/t25_runner"

"$TMP_DIR/t25_runner"
