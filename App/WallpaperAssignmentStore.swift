import Foundation

enum KindleWallSharedStorage {
    static let appGroupIdentifier = "group.com.marcuslo.KindleWall"
    static let generatedWallpapersDirectoryName = "generated-wallpapers"

    static func appGroupUserDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}

struct WallpaperAssignmentStore {
    static let assignmentKey = "reusableGeneratedWallpaperPathsByTarget"
    static let wallpaperAssignmentsAppGroupMigrationCompletedKey = "wallpaperAssignmentsAppGroupMigrationCompleted"

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

    let userDefaults: UserDefaults
    let fileManager: FileManager

    init(
        userDefaults: UserDefaults,
        fileManager: FileManager = .default
    ) {
        self.userDefaults = userDefaults
        self.fileManager = fileManager
    }

    func replace(_ wallpapers: [StoredGeneratedWallpaper]) {
        persistReusableGeneratedWallpaperPaths(Self.persistedWallpaperPaths(from: wallpapers))
    }

    func merge(_ wallpapers: [StoredGeneratedWallpaper]) {
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

    func clear() {
        userDefaults.removeObject(forKey: Self.assignmentKey)
    }

    func migrateLegacyAssignments(
        from legacyDefaults: UserDefaults,
        appGroupDefaults: UserDefaults,
        appGroupGeneratedWallpapersDirectoryURL: URL
    ) throws -> Bool {
        guard legacyDefaults.bool(forKey: Self.wallpaperAssignmentsAppGroupMigrationCompletedKey) == false else {
            return false
        }

        guard let legacyAssignments = legacyDefaults.dictionary(forKey: Self.assignmentKey), !legacyAssignments.isEmpty else {
            legacyDefaults.set(true, forKey: Self.wallpaperAssignmentsAppGroupMigrationCompletedKey)
            return true
        }

        let migratedWallpapers = try Self.buildMigratedWallpapers(
            from: legacyAssignments,
            fileManager: fileManager,
            appGroupGeneratedWallpapersDirectoryURL: appGroupGeneratedWallpapersDirectoryURL
        )

        guard !migratedWallpapers.isEmpty else {
            legacyDefaults.set(true, forKey: Self.wallpaperAssignmentsAppGroupMigrationCompletedKey)
            return true
        }

        let migratedPaths = Self.persistedWallpaperPaths(from: migratedWallpapers)
        appGroupDefaults.set(migratedPaths, forKey: Self.assignmentKey)
        guard appGroupDefaults.dictionary(forKey: Self.assignmentKey) as NSDictionary? == NSDictionary(dictionary: migratedPaths) else {
            appGroupDefaults.removeObject(forKey: Self.assignmentKey)
            throw MigrationError.appGroupAssignmentVerificationFailed
        }

        legacyDefaults.set(true, forKey: Self.wallpaperAssignmentsAppGroupMigrationCompletedKey)
        return true
    }

    func load() -> [StoredGeneratedWallpaper] {
        guard let storedPaths = userDefaults.dictionary(forKey: Self.assignmentKey) else {
            return []
        }

        var validPathsByTarget: [String: Any] = [:]
        validPathsByTarget.reserveCapacity(storedPaths.count)

        var validWallpapers: [StoredGeneratedWallpaper] = []
        validWallpapers.reserveCapacity(storedPaths.count)

        for (targetIdentifier, rawPathValue) in storedPaths {
            guard
                let persistedWallpaper = Self.persistedStoredWallpaper(from: rawPathValue)
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
            validPathsByTarget[normalizedTargetIdentifier] = Self.persistedStoredWallpaperValue(for: normalizedWallpaper)
            validWallpapers.append(normalizedWallpaper)
        }

        if validPathsByTarget.isEmpty {
            userDefaults.removeObject(forKey: Self.assignmentKey)
        } else if NSDictionary(dictionary: validPathsByTarget) != storedPaths as NSDictionary {
            userDefaults.set(validPathsByTarget, forKey: Self.assignmentKey)
        }

        return validWallpapers.sorted { lhs, rhs in
            lhs.targetIdentifier < rhs.targetIdentifier
        }
    }

    private func persistReusableGeneratedWallpaperPaths(_ persistedPaths: [String: Any]) {
        guard !persistedPaths.isEmpty else {
            userDefaults.removeObject(forKey: Self.assignmentKey)
            return
        }

        userDefaults.set(persistedPaths, forKey: Self.assignmentKey)
    }

    private func reusableGeneratedWallpaperPathsByTarget() -> [String: Any] {
        guard let storedPaths = userDefaults.dictionary(forKey: Self.assignmentKey) else {
            return [:]
        }

        var persistedPaths: [String: Any] = [:]
        persistedPaths.reserveCapacity(storedPaths.count)

        for (targetIdentifier, rawPathValue) in storedPaths {
            guard let wallpaper = Self.persistedStoredWallpaper(from: rawPathValue) else {
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

            persistedPaths[normalizedTargetIdentifier] = Self.persistedStoredWallpaperValue(
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

    private static func buildMigratedWallpapers(
        from legacyAssignments: [String: Any],
        fileManager: FileManager,
        appGroupGeneratedWallpapersDirectoryURL: URL
    ) throws -> [StoredGeneratedWallpaper] {
        try fileManager.createDirectory(
            at: appGroupGeneratedWallpapersDirectoryURL,
            withIntermediateDirectories: true
        )

        var migratedWallpapers: [StoredGeneratedWallpaper] = []
        migratedWallpapers.reserveCapacity(legacyAssignments.count)

        for (targetIdentifier, rawPathValue) in legacyAssignments {
            guard let persistedWallpaper = persistedStoredWallpaper(from: rawPathValue) else {
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

            let sourceURL = URL(fileURLWithPath: normalizedPath).standardizedFileURL
            guard fileManager.fileExists(atPath: sourceURL.path) else {
                continue
            }

            let destinationURL = appGroupGeneratedWallpapersDirectoryURL
                .appendingPathComponent(sourceURL.lastPathComponent, isDirectory: false)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)

            migratedWallpapers.append(
                StoredGeneratedWallpaper(
                    targetIdentifier: normalizedTargetIdentifier,
                    fileURL: destinationURL.standardizedFileURL,
                    pixelWidth: persistedWallpaper.pixelWidth,
                    pixelHeight: persistedWallpaper.pixelHeight,
                    backingScaleFactor: persistedWallpaper.backingScaleFactor,
                    originX: persistedWallpaper.originX,
                    originY: persistedWallpaper.originY
                )
            )
        }

        return migratedWallpapers.sorted { lhs, rhs in
            lhs.targetIdentifier < rhs.targetIdentifier
        }
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

    enum MigrationError: Error {
        case appGroupAssignmentVerificationFailed
    }
}
