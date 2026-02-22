import Foundation

enum RotationScheduleMode: String, CaseIterable {
    case manual
    case daily
    case onLaunch
    case every30Minutes

    static func fromStoredValue(_ value: Any?) -> RotationScheduleMode? {
        if let stringValue = value as? String {
            return fromStoredString(stringValue)
        }

        if let number = value as? NSNumber {
            return fromStoredIndex(number.intValue)
        }

        return nil
    }

    private static func fromStoredString(_ value: String) -> RotationScheduleMode? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "manual":
            return .manual
        case "daily":
            return .daily
        case "onlaunch", "on_launch":
            return .onLaunch
        case "every30minutes", "every30min", "every_30_minutes":
            return .every30Minutes
        default:
            return nil
        }
    }

    private static func fromStoredIndex(_ value: Int) -> RotationScheduleMode? {
        switch value {
        case 0:
            return .manual
        case 1:
            return .daily
        case 2:
            return .onLaunch
        case 3:
            return .every30Minutes
        default:
            return nil
        }
    }
}

extension UserDefaults {
    private enum ScheduleKeys {
        static let rotationMode = "rotationScheduleMode"
        static let dailyHour = "scheduleDailyHour"
        static let dailyMinute = "scheduleDailyMinute"
        static let lastChangedAt = "lastChangedAt"
    }

    private static let lastChangedAtParsers: [ISO8601DateFormatter] = {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let withoutFractionalSeconds = ISO8601DateFormatter()
        withoutFractionalSeconds.formatOptions = [.withInternetDateTime]

        return [withFractionalSeconds, withoutFractionalSeconds]
    }()

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

    var rotationScheduleMode: RotationScheduleMode {
        get {
            RotationScheduleMode.fromStoredValue(object(forKey: ScheduleKeys.rotationMode)) ?? .daily
        }
        set {
            set(newValue.rawValue, forKey: ScheduleKeys.rotationMode)
        }
    }

    var lastChangedAt: Date? {
        get {
            guard let rawValue = object(forKey: ScheduleKeys.lastChangedAt) else {
                return nil
            }

            if let date = rawValue as? Date {
                return date
            }

            if let timestamp = rawValue as? NSNumber {
                return Date(timeIntervalSince1970: timestamp.doubleValue)
            }

            if let string = rawValue as? String {
                if let timestamp = Double(string) {
                    return Date(timeIntervalSince1970: timestamp)
                }

                for parser in Self.lastChangedAtParsers {
                    if let parsedDate = parser.date(from: string) {
                        return parsedDate
                    }
                }
            }

            return nil
        }
        set {
            guard let newValue else {
                removeObject(forKey: ScheduleKeys.lastChangedAt)
                return
            }

            set(newValue.timeIntervalSince1970, forKey: ScheduleKeys.lastChangedAt)
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
