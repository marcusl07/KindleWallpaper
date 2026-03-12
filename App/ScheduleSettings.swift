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

struct StoredGeneratedWallpaper: Equatable {
    static let allScreensTargetIdentifier = "__all_screens__"

    let targetIdentifier: String
    let fileURL: URL
}

extension UserDefaults {
    private enum ScheduleKeys {
        static let rotationMode = "rotationScheduleMode"
        static let dailyHour = "scheduleDailyHour"
        static let dailyMinute = "scheduleDailyMinute"
        static let lastChangedAt = "lastChangedAt"
        static let capitalizeHighlightText = "capitalizeHighlightText"
        static let didPruneStaleWallpaperHistory = "didPruneStaleWallpaperHistory"
        static let reusableGeneratedWallpaperPathsByTarget = "reusableGeneratedWallpaperPathsByTarget"
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

    var capitalizeHighlightText: Bool {
        get {
            guard let rawValue = object(forKey: ScheduleKeys.capitalizeHighlightText) else {
                return false
            }

            if let number = rawValue as? NSNumber {
                return number.boolValue
            }

            if let string = rawValue as? String {
                let normalized = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                switch normalized {
                case "1", "true", "yes":
                    return true
                case "0", "false", "no":
                    return false
                default:
                    return false
                }
            }

            return false
        }
        set {
            set(newValue, forKey: ScheduleKeys.capitalizeHighlightText)
        }
    }

    var didPruneStaleWallpaperHistory: Bool {
        get {
            bool(forKey: ScheduleKeys.didPruneStaleWallpaperHistory)
        }
        set {
            set(newValue, forKey: ScheduleKeys.didPruneStaleWallpaperHistory)
        }
    }

    func storeReusableGeneratedWallpapers(_ wallpapers: [StoredGeneratedWallpaper]) {
        guard !wallpapers.isEmpty else {
            removeObject(forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget)
            return
        }

        let persistedPaths = Dictionary(
            wallpapers.map { wallpaper in
                (wallpaper.targetIdentifier, wallpaper.fileURL.standardizedFileURL.path)
            },
            uniquingKeysWith: { _, latest in latest }
        )
        set(persistedPaths, forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget)
    }

    func loadReusableGeneratedWallpapers(
        fileManager: FileManager = .default
    ) -> [StoredGeneratedWallpaper] {
        guard let storedPaths = dictionary(forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget) else {
            return []
        }

        var validPathsByTarget: [String: String] = [:]
        validPathsByTarget.reserveCapacity(storedPaths.count)

        var validWallpapers: [StoredGeneratedWallpaper] = []
        validWallpapers.reserveCapacity(storedPaths.count)

        for (targetIdentifier, rawPathValue) in storedPaths {
            guard
                let path = rawPathValue as? String
            else {
                continue
            }

            let normalizedTargetIdentifier = targetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !normalizedTargetIdentifier.isEmpty,
                !normalizedPath.isEmpty
            else {
                continue
            }

            let fileURL = URL(fileURLWithPath: normalizedPath).standardizedFileURL
            guard fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }

            validPathsByTarget[normalizedTargetIdentifier] = fileURL.path
            validWallpapers.append(
                StoredGeneratedWallpaper(
                    targetIdentifier: normalizedTargetIdentifier,
                    fileURL: fileURL
                )
            )
        }

        if validPathsByTarget.isEmpty {
            removeObject(forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget)
        } else if NSDictionary(dictionary: validPathsByTarget) != storedPaths as NSDictionary {
            set(validPathsByTarget, forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget)
        }

        return validWallpapers.sorted { lhs, rhs in
            lhs.targetIdentifier < rhs.targetIdentifier
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
