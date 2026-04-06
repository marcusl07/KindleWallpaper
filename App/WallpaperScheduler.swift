import Foundation

protocol WallpaperSchedulerTimer: AnyObject {
    func invalidate()
}

private final class FoundationWallpaperSchedulerTimer: WallpaperSchedulerTimer {
    private var timer: Timer?

    init(interval: TimeInterval, handler: @escaping () -> Void) {
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
            handler()
        }
    }

    func invalidate() {
        timer?.invalidate()
        timer = nil
    }
}

final class WallpaperScheduler {
    typealias RotateWallpaper = () -> Bool
    typealias DateProvider = () -> Date
    typealias RepeatingTimerFactory = (_ interval: TimeInterval, _ handler: @escaping () -> Void) -> WallpaperSchedulerTimer

    private enum Trigger {
        case appLaunch
        case timerTick
    }

    private let userDefaults: UserDefaults
    private let rotateWallpaper: RotateWallpaper
    private let now: DateProvider
    private let calendar: Calendar
    private let repeatingTimerFactory: RepeatingTimerFactory

    private var repeatingTimer: WallpaperSchedulerTimer?
    private var hasRunLaunchCheck = false
    private var isRotating = false
    private var pendingDailyScheduledTime: Date?
    private var deferredDailyCheckUntil: Date?
    private var deferredEveryThirtyMinuteCheckUntil: Date?

    init(
        userDefaults: UserDefaults = .standard,
        rotateWallpaper: @escaping RotateWallpaper,
        now: @escaping DateProvider = Date.init,
        calendar: Calendar = .current,
        repeatingTimerFactory: @escaping RepeatingTimerFactory = { interval, handler in
            FoundationWallpaperSchedulerTimer(interval: interval, handler: handler)
        },
        autoStart: Bool = true
    ) {
        self.userDefaults = userDefaults
        self.rotateWallpaper = rotateWallpaper
        self.now = now
        self.calendar = calendar
        self.repeatingTimerFactory = repeatingTimerFactory

        if autoStart {
            start()
        }
    }

    deinit {
        stop()
    }

    func start() {
        guard repeatingTimer == nil else {
            return
        }

        if hasRunLaunchCheck {
            evaluateSchedule(trigger: .timerTick)
        } else {
            hasRunLaunchCheck = true
            evaluateSchedule(trigger: .appLaunch)
        }

        repeatingTimer = repeatingTimerFactory(60) { [weak self] in
            self?.evaluateSchedule(trigger: .timerTick)
        }
    }

    func stop() {
        repeatingTimer?.invalidate()
        repeatingTimer = nil
    }

    func checkNow() {
        evaluateSchedule(trigger: .timerTick)
    }

    private func evaluateSchedule(trigger: Trigger) {
        let mode = userDefaults.rotationScheduleMode

        switch mode {
        case .manual:
            pendingDailyScheduledTime = nil
            deferredDailyCheckUntil = nil
            deferredEveryThirtyMinuteCheckUntil = nil
            return
        case .onLaunch:
            pendingDailyScheduledTime = nil
            deferredDailyCheckUntil = nil
            deferredEveryThirtyMinuteCheckUntil = nil
            guard trigger == .appLaunch else {
                return
            }
            _ = performRotationIfNeeded()
        case .every30Minutes:
            pendingDailyScheduledTime = nil
            deferredDailyCheckUntil = nil
            evaluateEveryThirtyMinuteSchedule(trigger: trigger)
        case .daily:
            deferredEveryThirtyMinuteCheckUntil = nil
            if trigger == .appLaunch {
                let currentTime = now()
                let todayScheduledTime = Self.scheduledTimeForToday(
                    at: currentTime,
                    scheduleHour: userDefaults.scheduleDailyHour,
                    scheduleMinute: userDefaults.scheduleDailyMinute,
                    calendar: calendar
                )

                if currentTime >= todayScheduledTime {
                    deferredDailyCheckUntil = Self.nextScheduledTime(
                        after: currentTime,
                        scheduleHour: userDefaults.scheduleDailyHour,
                        scheduleMinute: userDefaults.scheduleDailyMinute,
                        calendar: calendar
                    )
                    return
                }
            }
            evaluateDailySchedule()
        }
    }

    private func evaluateEveryThirtyMinuteSchedule(trigger: Trigger) {
        let currentTime = now()

        if trigger == .appLaunch {
            deferredEveryThirtyMinuteCheckUntil = currentTime.addingTimeInterval(30 * 60)
            return
        }

        if let deferredEveryThirtyMinuteCheckUntil {
            guard currentTime >= deferredEveryThirtyMinuteCheckUntil else {
                return
            }
            self.deferredEveryThirtyMinuteCheckUntil = nil
        }

        guard Self.shouldRotateEveryThirtyMinutes(now: currentTime, lastChangedAt: userDefaults.lastChangedAt) else {
            return
        }

        _ = performRotationIfNeeded()
    }

    private func evaluateDailySchedule() {
        let currentTime = now()
        let todayScheduledTime = Self.scheduledTimeForToday(
            at: currentTime,
            scheduleHour: userDefaults.scheduleDailyHour,
            scheduleMinute: userDefaults.scheduleDailyMinute,
            calendar: calendar
        )

        if let deferredDailyCheckUntil {
            guard currentTime >= deferredDailyCheckUntil else {
                return
            }
            self.deferredDailyCheckUntil = nil
        }

        if let pendingDailyScheduledTime {
            if currentTime >= pendingDailyScheduledTime {
                if performRotationIfNeeded() {
                    self.pendingDailyScheduledTime = nil
                }
                return
            } else {
                return
            }
        }

        guard Self.shouldRotateDaily(
            now: currentTime,
            lastChangedAt: userDefaults.lastChangedAt,
            scheduleHour: userDefaults.scheduleDailyHour,
            scheduleMinute: userDefaults.scheduleDailyMinute,
            calendar: calendar
        ) else {
            return
        }

        if performRotationIfNeeded() {
            pendingDailyScheduledTime = nil
        } else {
            pendingDailyScheduledTime = todayScheduledTime
        }
    }

    @discardableResult
    private func performRotationIfNeeded() -> Bool {
        guard !isRotating else {
            return false
        }

        isRotating = true
        defer {
            isRotating = false
        }

        return rotateWallpaper()
    }

    static func shouldRotateEveryThirtyMinutes(now: Date, lastChangedAt: Date?) -> Bool {
        guard let lastChangedAt else {
            return true
        }

        return now.timeIntervalSince(lastChangedAt) >= (30 * 60)
    }

    static func shouldRotateDaily(
        now: Date,
        lastChangedAt: Date?,
        scheduleHour: Int,
        scheduleMinute: Int,
        calendar: Calendar
    ) -> Bool {
        let scheduledTime = scheduledTimeForToday(
            at: now,
            scheduleHour: scheduleHour,
            scheduleMinute: scheduleMinute,
            calendar: calendar
        )

        guard now >= scheduledTime else {
            return false
        }

        guard let lastChangedAt else {
            return true
        }

        return lastChangedAt < scheduledTime
    }

    static func scheduledTimeForToday(
        at referenceDate: Date,
        scheduleHour: Int,
        scheduleMinute: Int,
        calendar: Calendar
    ) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: referenceDate)
        components.hour = min(max(scheduleHour, 0), 23)
        components.minute = min(max(scheduleMinute, 0), 59)
        components.second = 0

        if let scheduledDate = calendar.date(from: components) {
            return scheduledDate
        }

        let startOfDay = calendar.startOfDay(for: referenceDate)
        let matchingComponents = DateComponents(hour: components.hour, minute: components.minute, second: 0)
        if let fallback = calendar.nextDate(
            after: startOfDay.addingTimeInterval(-1),
            matching: matchingComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ), calendar.isDate(fallback, inSameDayAs: referenceDate) {
            return fallback
        }

        return startOfDay
    }

    static func nextScheduledTime(
        after referenceDate: Date,
        scheduleHour: Int,
        scheduleMinute: Int,
        calendar: Calendar
    ) -> Date {
        let hour = min(max(scheduleHour, 0), 23)
        let minute = min(max(scheduleMinute, 0), 59)
        let components = DateComponents(hour: hour, minute: minute, second: 0)

        if let nextScheduledDate = calendar.nextDate(
            after: referenceDate,
            matching: components,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        ) {
            return nextScheduledDate
        }

        return scheduledTimeForToday(
            at: referenceDate.addingTimeInterval(24 * 60 * 60),
            scheduleHour: hour,
            scheduleMinute: minute,
            calendar: calendar
        )
    }
}
