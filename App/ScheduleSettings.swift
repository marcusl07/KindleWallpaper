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
        static let reusableGeneratedWallpaperPathsByTarget = "reusableGeneratedWallpaperPathsByTarget"
    }

    private enum StoredWallpaperKeys {
        static let path = "path"
        static let pixelWidth = "pixelWidth"
        static let pixelHeight = "pixelHeight"
        static let backingScaleFactor = "backingScaleFactor"
        static let originX = "originX"
        static let originY = "originY"
    }

    private struct PersistedStoredWallpaper {
        let path: String
        let pixelWidth: Int?
        let pixelHeight: Int?
        let backingScaleFactor: Double?
        let originX: Int?
        let originY: Int?
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

    func replaceReusableGeneratedWallpapers(_ wallpapers: [StoredGeneratedWallpaper]) {
        persistReusableGeneratedWallpaperPaths(Self.persistedWallpaperPaths(from: wallpapers))
    }

    func mergeReusableGeneratedWallpapers(_ wallpapers: [StoredGeneratedWallpaper]) {
        guard !wallpapers.isEmpty else {
            return
        }

        var persistedPaths = reusableGeneratedWallpaperPathsByTarget()
        let mergedPaths = Self.persistedWallpaperPaths(from: wallpapers)
        for (targetIdentifier, path) in mergedPaths {
            persistedPaths[targetIdentifier] = path
        }
        persistReusableGeneratedWallpaperPaths(persistedPaths)
    }

    func clearReusableGeneratedWallpapers() {
        removeObject(forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget)
    }

    func loadReusableGeneratedWallpapers(
        fileManager: FileManager = .default
    ) -> [StoredGeneratedWallpaper] {
        guard let storedPaths = dictionary(forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget) else {
            return []
        }

        var validPathsByTarget: [String: Any] = [:]
        validPathsByTarget.reserveCapacity(storedPaths.count)

        var validWallpapers: [StoredGeneratedWallpaper] = []
        validWallpapers.reserveCapacity(storedPaths.count)

        for (targetIdentifier, rawPathValue) in storedPaths {
            guard
                let persistedWallpaper = persistedStoredWallpaper(from: rawPathValue)
            else {
                continue
            }

            let normalizedTargetIdentifier = targetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPath = persistedWallpaper.path.trimmingCharacters(in: .whitespacesAndNewlines)
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

            let normalizedWallpaper = StoredGeneratedWallpaper(
                targetIdentifier: normalizedTargetIdentifier,
                fileURL: fileURL,
                pixelWidth: persistedWallpaper.pixelWidth,
                pixelHeight: persistedWallpaper.pixelHeight,
                backingScaleFactor: persistedWallpaper.backingScaleFactor,
                originX: persistedWallpaper.originX,
                originY: persistedWallpaper.originY
            )
            validPathsByTarget[normalizedTargetIdentifier] = persistedStoredWallpaperValue(for: normalizedWallpaper)
            validWallpapers.append(normalizedWallpaper)
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

    private func persistedStoredWallpaper(from rawValue: Any) -> PersistedStoredWallpaper? {
        Self.persistedStoredWallpaper(from: rawValue)
    }

    private static func persistedStoredWallpaper(from rawValue: Any) -> PersistedStoredWallpaper? {
        if let path = rawValue as? String {
            return PersistedStoredWallpaper(
                path: path,
                pixelWidth: nil,
                pixelHeight: nil,
                backingScaleFactor: nil,
                originX: nil,
                originY: nil
            )
        }

        guard let dictionary = rawValue as? [String: Any] else {
            return nil
        }

        guard let path = dictionary[StoredWallpaperKeys.path] as? String else {
            return nil
        }

        return PersistedStoredWallpaper(
            path: path,
            pixelWidth: integer(from: dictionary[StoredWallpaperKeys.pixelWidth]),
            pixelHeight: integer(from: dictionary[StoredWallpaperKeys.pixelHeight]),
            backingScaleFactor: double(from: dictionary[StoredWallpaperKeys.backingScaleFactor]),
            originX: integer(from: dictionary[StoredWallpaperKeys.originX]),
            originY: integer(from: dictionary[StoredWallpaperKeys.originY])
        )
    }

    private func persistedStoredWallpaperValue(for wallpaper: StoredGeneratedWallpaper) -> [String: Any] {
        Self.persistedStoredWallpaperValue(for: wallpaper)
    }

    private static func persistedStoredWallpaperValue(for wallpaper: StoredGeneratedWallpaper) -> [String: Any] {
        var value: [String: Any] = [
            StoredWallpaperKeys.path: wallpaper.fileURL.standardizedFileURL.path
        ]

        if let pixelWidth = wallpaper.pixelWidth {
            value[StoredWallpaperKeys.pixelWidth] = pixelWidth
        }
        if let pixelHeight = wallpaper.pixelHeight {
            value[StoredWallpaperKeys.pixelHeight] = pixelHeight
        }
        if let backingScaleFactor = wallpaper.backingScaleFactor {
            value[StoredWallpaperKeys.backingScaleFactor] = backingScaleFactor
        }
        if let originX = wallpaper.originX {
            value[StoredWallpaperKeys.originX] = originX
        }
        if let originY = wallpaper.originY {
            value[StoredWallpaperKeys.originY] = originY
        }

        return value
    }

    private static func integer(from rawValue: Any?) -> Int? {
        if let number = rawValue as? NSNumber {
            return number.intValue
        }

        if let string = rawValue as? String {
            return Int(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private static func double(from rawValue: Any?) -> Double? {
        if let number = rawValue as? NSNumber {
            return number.doubleValue
        }

        if let string = rawValue as? String {
            return Double(string.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return nil
    }

    private func persistReusableGeneratedWallpaperPaths(_ persistedPaths: [String: Any]) {
        guard !persistedPaths.isEmpty else {
            removeObject(forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget)
            return
        }

        set(persistedPaths, forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget)
    }

    private func reusableGeneratedWallpaperPathsByTarget() -> [String: Any] {
        guard let storedPaths = dictionary(forKey: ScheduleKeys.reusableGeneratedWallpaperPathsByTarget) else {
            return [:]
        }

        var persistedPaths: [String: Any] = [:]
        persistedPaths.reserveCapacity(storedPaths.count)

        for (targetIdentifier, rawPathValue) in storedPaths {
            guard let wallpaper = persistedStoredWallpaper(from: rawPathValue) else {
                continue
            }

            let normalizedTargetIdentifier = targetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedPath = wallpaper.path.trimmingCharacters(in: .whitespacesAndNewlines)
            guard
                !normalizedTargetIdentifier.isEmpty,
                !normalizedPath.isEmpty
            else {
                continue
            }

            persistedPaths[normalizedTargetIdentifier] = persistedStoredWallpaperValue(
                for: StoredGeneratedWallpaper(
                    targetIdentifier: normalizedTargetIdentifier,
                    fileURL: URL(fileURLWithPath: normalizedPath).standardizedFileURL,
                    pixelWidth: wallpaper.pixelWidth,
                    pixelHeight: wallpaper.pixelHeight,
                    backingScaleFactor: wallpaper.backingScaleFactor,
                    originX: wallpaper.originX,
                    originY: wallpaper.originY
                )
            )
        }

        return persistedPaths
    }

    private static func persistedWallpaperPaths(from wallpapers: [StoredGeneratedWallpaper]) -> [String: Any] {
        Dictionary(
            wallpapers.map { wallpaper in
                (
                    wallpaper.targetIdentifier.trimmingCharacters(in: .whitespacesAndNewlines),
                    persistedStoredWallpaperValue(for: wallpaper)
                )
            }.filter { !$0.0.isEmpty },
            uniquingKeysWith: { _, latest in latest }
        )
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
