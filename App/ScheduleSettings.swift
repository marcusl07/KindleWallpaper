import Foundation

extension UserDefaults {
    private enum ScheduleKeys {
        static let dailyHour = "scheduleDailyHour"
        static let dailyMinute = "scheduleDailyMinute"
    }

    var scheduleDailyHour: Int {
        get {
            guard let storedValue = integerIfPresent(forKey: ScheduleKeys.dailyHour) else {
                return 9
            }
            return Self.normalizedDailyHour(storedValue)
        }
        set {
            set(Self.normalizedDailyHour(newValue), forKey: ScheduleKeys.dailyHour)
        }
    }

    var scheduleDailyMinute: Int {
        get {
            guard let storedValue = integerIfPresent(forKey: ScheduleKeys.dailyMinute) else {
                return 0
            }
            return Self.normalizedDailyMinute(storedValue)
        }
        set {
            set(Self.normalizedDailyMinute(newValue), forKey: ScheduleKeys.dailyMinute)
        }
    }

    private func integerIfPresent(forKey key: String) -> Int? {
        guard let value = object(forKey: key) else {
            return nil
        }

        if let number = value as? NSNumber {
            return number.intValue
        }

        if let string = value as? String {
            return Int(string)
        }

        return nil
    }

    private static func normalizedDailyHour(_ value: Int) -> Int {
        min(max(value, 0), 23)
    }

    private static func normalizedDailyMinute(_ value: Int) -> Int {
        min(max(value, 0), 59)
    }
}
