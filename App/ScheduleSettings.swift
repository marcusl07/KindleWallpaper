import Foundation

enum RotationScheduleMode: String, CaseIterable {
    case manual
    case daily
    case onLaunch
    case everyInterval

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
        case "everyinterval", "every_interval", "interval":
            return .everyInterval
        case "every30minutes", "every30min", "every_30_minutes":
            return .everyInterval
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
            return .everyInterval
        default:
            return nil
        }
    }
}

struct StoredGeneratedWallpaper: Equatable {
    static let allScreensTargetIdentifier = "__all_screens__"

    let targetIdentifier: String
    let fileURL: URL
    let pixelWidth: Int?
    let pixelHeight: Int?
    let backingScaleFactor: Double?
    let originX: Int?
    let originY: Int?

    init(
        targetIdentifier: String,
        fileURL: URL,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        backingScaleFactor: Double? = nil,
        originX: Int? = nil,
        originY: Int? = nil
    ) {
        self.targetIdentifier = targetIdentifier
        self.fileURL = fileURL
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.backingScaleFactor = backingScaleFactor
        self.originX = originX
        self.originY = originY
    }
}

extension UserDefaults {
    private enum ScheduleKeys {
        static let rotationMode = "rotationScheduleMode"
        static let dailyHour = "scheduleDailyHour"
        static let dailyMinute = "scheduleDailyMinute"
        static let intervalMinutes = "scheduleIntervalMinutes"
        static let lastChangedAt = "lastChangedAt"
        static let capitalizeHighlightText = "capitalizeHighlightText"
        static let didPruneStaleWallpaperHistory = "didPruneStaleWallpaperHistory"
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

    var scheduleIntervalMinutes: Int {
        get {
            guard let storedValue = integerIfPresent(forKey: ScheduleKeys.intervalMinutes) else {
                return 30
            }
            return Self.normalizedScheduleIntervalMinutes(storedValue)
        }
        set {
            set(Self.normalizedScheduleIntervalMinutes(newValue), forKey: ScheduleKeys.intervalMinutes)
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

    var wallpaperAssignmentsAppGroupMigrationCompleted: Bool {
        get {
            bool(forKey: WallpaperAssignmentStore.wallpaperAssignmentsAppGroupMigrationCompletedKey)
        }
        set {
            set(newValue, forKey: WallpaperAssignmentStore.wallpaperAssignmentsAppGroupMigrationCompletedKey)
        }
    }

    func replaceReusableGeneratedWallpapers(_ wallpapers: [StoredGeneratedWallpaper]) {
        WallpaperAssignmentStore(userDefaults: self).replace(wallpapers)
    }

    func mergeReusableGeneratedWallpapers(_ wallpapers: [StoredGeneratedWallpaper]) {
        WallpaperAssignmentStore(userDefaults: self).merge(wallpapers)
    }

    func clearReusableGeneratedWallpapers() {
        WallpaperAssignmentStore(userDefaults: self).clear()
    }

    func loadReusableGeneratedWallpapers(
        fileManager: FileManager = .default
    ) -> [StoredGeneratedWallpaper] {
        WallpaperAssignmentStore(userDefaults: self, fileManager: fileManager).load()
    }

    func migrateWallpaperAssignmentsToAppGroupIfNeeded(
        appGroupDefaults: UserDefaults,
        appGroupGeneratedWallpapersDirectoryURL: URL,
        fileManager: FileManager = .default
    ) throws -> Bool {
        try WallpaperAssignmentStore(userDefaults: self, fileManager: fileManager).migrateLegacyAssignments(
            from: self,
            appGroupDefaults: appGroupDefaults,
            appGroupGeneratedWallpapersDirectoryURL: appGroupGeneratedWallpapersDirectoryURL
        )
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

    private static func normalizedScheduleIntervalMinutes(_ value: Int) -> Int {
        min(max(value, 1), (23 * 60) + 59)
    }
}
