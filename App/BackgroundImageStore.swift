import Foundation

struct BackgroundImageStore {
    struct BackgroundImageItem: Equatable, Identifiable {
        let id: UUID
        let fileURL: URL
        let addedAt: Date
    }

    enum MigrationFailureReason: Equatable {
        case missingLegacyFile(path: String)
        case unreadableLegacyFile(path: String)
        case copyFailed(path: String)
        case manifestWriteFailed
        case manifestDecodeFailed

        var message: String {
            switch self {
            case .missingLegacyFile(let path):
                return "Legacy background file is missing at \(path)."
            case .unreadableLegacyFile(let path):
                return "Legacy background file is unreadable at \(path)."
            case .copyFailed(let path):
                return "Failed to copy legacy background file from \(path)."
            case .manifestWriteFailed:
                return "Failed to persist background collection metadata."
            case .manifestDecodeFailed:
                return "Background collection metadata is corrupted."
            }
        }
    }

    enum LoadCollectionOutcome: Equatable {
        case success
        case empty
        case partiallyRecovered(removedInvalidEntries: Int)
        case migrationFailed(MigrationFailureReason)
    }

    struct CollectionLoadResult: Equatable {
        let items: [BackgroundImageItem]
        let outcome: LoadCollectionOutcome

        var urls: [URL] {
            items.map(\.fileURL)
        }
    }

    enum StoreError: LocalizedError {
        case emptySourceList
        case sourceFileMissing(path: String)
        case sourceFileUnreadable(path: String)
        case manifestDecodeFailed
        case manifestWriteFailed
        case failedToCopySource(path: String, message: String)
        case cannotRemoveLastImage

        var errorDescription: String? {
            switch self {
            case .emptySourceList:
                return "At least one source image is required."
            case .sourceFileMissing(let path):
                return "Background image source file does not exist at \(path)."
            case .sourceFileUnreadable(let path):
                return "Background image source file is unreadable at \(path)."
            case .manifestDecodeFailed:
                return "Background image collection metadata is corrupted."
            case .manifestWriteFailed:
                return "Failed to persist background image collection metadata."
            case .failedToCopySource(let path, let message):
                return "Failed to copy background image from \(path): \(message)"
            case .cannotRemoveLastImage:
                return "At least one background image must remain."
            }
        }
    }

    private enum Keys {
        static let backgroundImagePath = "backgroundImagePath"
    }

    private enum Constants {
        static let backgroundsDirectoryName = "backgrounds"
        static let manifestFilename = "backgrounds_manifest.json"
    }

    private struct Manifest: Codable {
        let version: Int
        var records: [ManifestRecord]
    }

    private struct ManifestRecord: Codable, Equatable {
        let id: UUID
        let filename: String
        let addedAt: Date
    }

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let appSupportDirectoryURL: URL
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        appSupportDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults

        if let appSupportDirectoryURL {
            self.appSupportDirectoryURL = appSupportDirectoryURL
        } else {
            self.appSupportDirectoryURL = AppSupportPaths.kindleWallDirectory(fileManager: fileManager)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        jsonDecoder = decoder

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        jsonEncoder = encoder
    }

    @discardableResult
    func saveBackgroundImage(from sourceURL: URL) throws -> URL {
        let items = try replaceBackgroundImages(with: [sourceURL])
        guard let first = items.first else {
            throw StoreError.emptySourceList
        }
        return first.fileURL
    }

    @discardableResult
    func addBackgroundImage(from sourceURL: URL) throws -> BackgroundImageItem {
        let existing = try loadManifestOrThrow()
        let copied = try copySourceImage(sourceURL, preferredFilename: nil)
        let record = ManifestRecord(
            id: UUID(),
            filename: copied.lastPathComponent,
            addedAt: Date()
        )

        var updatedRecords = existing.records
        updatedRecords.append(record)

        do {
            try writeManifest(Manifest(version: existing.version, records: updatedRecords))
        } catch {
            try? fileManager.removeItem(at: copied)
            throw StoreError.manifestWriteFailed
        }

        clearLegacyPathKey()
        cleanupOrphanFiles(keeping: Set(updatedRecords.map(\.filename)))

        return BackgroundImageItem(id: record.id, fileURL: copied, addedAt: record.addedAt)
    }

    @discardableResult
    func removeBackgroundImage(id: UUID) throws -> [BackgroundImageItem] {
        let manifest = try loadManifestOrThrow()
        let existingItems = materializeItems(from: manifest.records).items

        guard existingItems.count > 1 else {
            throw StoreError.cannotRemoveLastImage
        }

        guard let removedItem = existingItems.first(where: { $0.id == id }) else {
            return existingItems
        }

        let remainingRecords = manifest.records.filter { $0.id != id }
        do {
            try writeManifest(Manifest(version: manifest.version, records: remainingRecords))
        } catch {
            throw StoreError.manifestWriteFailed
        }

        try? fileManager.removeItem(at: removedItem.fileURL)
        cleanupOrphanFiles(keeping: Set(remainingRecords.map(\.filename)))

        return materializeItems(from: remainingRecords).items
    }

    @discardableResult
    func replaceBackgroundImages(with sourceURLs: [URL]) throws -> [BackgroundImageItem] {
        guard !sourceURLs.isEmpty else {
            throw StoreError.emptySourceList
        }

        try ensureBackgroundsDirectory()
        let existing = try loadManifestOrThrow()

        var copiedURLs: [URL] = []
        copiedURLs.reserveCapacity(sourceURLs.count)
        var records: [ManifestRecord] = []
        records.reserveCapacity(sourceURLs.count)

        do {
            for sourceURL in sourceURLs {
                let copiedURL = try copySourceImage(sourceURL, preferredFilename: nil)
                copiedURLs.append(copiedURL)
                records.append(
                    ManifestRecord(
                        id: UUID(),
                        filename: copiedURL.lastPathComponent,
                        addedAt: Date()
                    )
                )
            }
        } catch {
            for copiedURL in copiedURLs {
                try? fileManager.removeItem(at: copiedURL)
            }
            throw error
        }

        do {
            try writeManifest(Manifest(version: existing.version, records: records))
        } catch {
            for copiedURL in copiedURLs {
                try? fileManager.removeItem(at: copiedURL)
            }
            throw StoreError.manifestWriteFailed
        }

        clearLegacyPathKey()
        cleanupOrphanFiles(keeping: Set(records.map(\.filename)))

        return records.map { record in
            BackgroundImageItem(
                id: record.id,
                fileURL: backgroundsDirectoryURL().appendingPathComponent(record.filename, isDirectory: false),
                addedAt: record.addedAt
            )
        }
    }

    func loadBackgroundImageCollection() -> CollectionLoadResult {
        if fileManager.fileExists(atPath: manifestURL().path) {
            guard let manifest = loadManifest() else {
                return CollectionLoadResult(
                    items: [],
                    outcome: .migrationFailed(.manifestDecodeFailed)
                )
            }

            let materialized = materializeItems(from: manifest.records)
            if materialized.removedInvalidEntries > 0 {
                let recoveredRecords = materialized.items.map {
                    ManifestRecord(id: $0.id, filename: $0.fileURL.lastPathComponent, addedAt: $0.addedAt)
                }

                do {
                    try writeManifest(Manifest(version: manifest.version, records: recoveredRecords))
                } catch {
                    return CollectionLoadResult(
                        items: materialized.items,
                        outcome: .migrationFailed(.manifestWriteFailed)
                    )
                }

                cleanupOrphanFiles(keeping: Set(recoveredRecords.map(\.filename)))
                return CollectionLoadResult(
                    items: materialized.items,
                    outcome: .partiallyRecovered(removedInvalidEntries: materialized.removedInvalidEntries)
                )
            }

            if materialized.items.isEmpty {
                return CollectionLoadResult(items: [], outcome: .empty)
            }

            return CollectionLoadResult(items: materialized.items, outcome: .success)
        }

        return migrateLegacyBackgroundPathIfNeeded()
    }

    func loadBackgroundImageURLs() -> [URL] {
        loadBackgroundImageCollection().urls
    }

    func loadBackgroundImageURL() -> URL? {
        loadBackgroundImageURLs().first
    }

    private func migrateLegacyBackgroundPathIfNeeded() -> CollectionLoadResult {
        guard let storedPath = userDefaults.string(forKey: Keys.backgroundImagePath),
              !storedPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return CollectionLoadResult(items: [], outcome: .empty)
        }

        let legacyURL = URL(fileURLWithPath: storedPath)
        guard fileManager.fileExists(atPath: legacyURL.path) else {
            clearLegacyPathKey()
            return CollectionLoadResult(
                items: [],
                outcome: .migrationFailed(.missingLegacyFile(path: legacyURL.path))
            )
        }

        guard fileManager.isReadableFile(atPath: legacyURL.path) else {
            clearLegacyPathKey()
            return CollectionLoadResult(
                items: [],
                outcome: .migrationFailed(.unreadableLegacyFile(path: legacyURL.path))
            )
        }

        do {
            try ensureBackgroundsDirectory()
        } catch {
            return CollectionLoadResult(
                items: [],
                outcome: .migrationFailed(.manifestWriteFailed)
            )
        }

        let copiedURL: URL
        do {
            copiedURL = try copySourceImage(legacyURL, preferredFilename: nil)
        } catch {
            return CollectionLoadResult(
                items: [],
                outcome: .migrationFailed(.copyFailed(path: legacyURL.path))
            )
        }

        let record = ManifestRecord(
            id: UUID(),
            filename: copiedURL.lastPathComponent,
            addedAt: Date()
        )
        do {
            try writeManifest(Manifest(version: 1, records: [record]))
        } catch {
            try? fileManager.removeItem(at: copiedURL)
            return CollectionLoadResult(
                items: [],
                outcome: .migrationFailed(.manifestWriteFailed)
            )
        }

        clearLegacyPathKey()
        cleanupOrphanFiles(keeping: Set([record.filename]))

        return CollectionLoadResult(
            items: [
                BackgroundImageItem(
                    id: record.id,
                    fileURL: copiedURL,
                    addedAt: record.addedAt
                )
            ],
            outcome: .success
        )
    }

    private func loadManifestOrThrow() throws -> Manifest {
        if !fileManager.fileExists(atPath: manifestURL().path) {
            return Manifest(version: 1, records: [])
        }

        guard let manifest = loadManifest() else {
            throw StoreError.manifestDecodeFailed
        }
        return manifest
    }

    private func loadManifest() -> Manifest? {
        let url = manifestURL()
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }

        guard let data = try? Data(contentsOf: url) else {
            return nil
        }

        return try? jsonDecoder.decode(Manifest.self, from: data)
    }

    private func materializeItems(from records: [ManifestRecord]) -> (items: [BackgroundImageItem], removedInvalidEntries: Int) {
        var validItems: [BackgroundImageItem] = []
        validItems.reserveCapacity(records.count)
        var removedCount = 0

        for record in records {
            let filename = record.filename.trimmingCharacters(in: .whitespacesAndNewlines)
            if filename.isEmpty {
                removedCount += 1
                continue
            }

            let fileURL = backgroundsDirectoryURL().appendingPathComponent(filename, isDirectory: false)
            guard fileManager.fileExists(atPath: fileURL.path), fileManager.isReadableFile(atPath: fileURL.path) else {
                removedCount += 1
                continue
            }

            validItems.append(
                BackgroundImageItem(
                    id: record.id,
                    fileURL: fileURL,
                    addedAt: record.addedAt
                )
            )
        }

        validItems.sort { lhs, rhs in
            if lhs.addedAt == rhs.addedAt {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.addedAt < rhs.addedAt
        }

        return (items: validItems, removedInvalidEntries: removedCount)
    }

    private func writeManifest(_ manifest: Manifest) throws {
        try ensureBackgroundsDirectory()

        do {
            let data = try jsonEncoder.encode(manifest)
            try data.write(to: manifestURL(), options: .atomic)
        } catch {
            throw StoreError.manifestWriteFailed
        }
    }

    private func ensureBackgroundsDirectory() throws {
        try fileManager.createDirectory(
            at: backgroundsDirectoryURL(),
            withIntermediateDirectories: true
        )
    }

    private func clearLegacyPathKey() {
        userDefaults.removeObject(forKey: Keys.backgroundImagePath)
    }

    private func copySourceImage(_ sourceURL: URL, preferredFilename: String?) throws -> URL {
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw StoreError.sourceFileMissing(path: sourceURL.path)
        }
        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw StoreError.sourceFileUnreadable(path: sourceURL.path)
        }

        try ensureBackgroundsDirectory()
        let destinationFilename = preferredFilename ?? makeDestinationFilename(for: sourceURL)
        let destinationURL = backgroundsDirectoryURL().appendingPathComponent(destinationFilename, isDirectory: false)

        do {
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            throw StoreError.failedToCopySource(path: sourceURL.path, message: error.localizedDescription)
        }
    }

    private func makeDestinationFilename(for sourceURL: URL) -> String {
        let extensionPart = sanitizedExtension(sourceURL.pathExtension)
        let fileID = UUID().uuidString.lowercased()
        if extensionPart.isEmpty {
            return "\(fileID).img"
        }
        return "\(fileID).\(extensionPart)"
    }

    private func sanitizedExtension(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let allowed = trimmed.filter { character in
            character.isLetter || character.isNumber
        }
        return allowed
    }

    private func cleanupOrphanFiles(keeping keptFilenames: Set<String>) {
        let directoryURL = backgroundsDirectoryURL()
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let fileURLs = (try? fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )) ?? []

        for fileURL in fileURLs {
            let name = fileURL.lastPathComponent
            if name == Constants.manifestFilename {
                continue
            }
            if keptFilenames.contains(name) {
                continue
            }
            try? fileManager.removeItem(at: fileURL)
        }
    }

    private func backgroundsDirectoryURL() -> URL {
        appSupportDirectoryURL.appendingPathComponent(Constants.backgroundsDirectoryName, isDirectory: true)
    }

    private func manifestURL() -> URL {
        backgroundsDirectoryURL().appendingPathComponent(Constants.manifestFilename, isDirectory: false)
    }
}
