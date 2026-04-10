import Foundation
#if canImport(AppKit)
import AppKit
#endif

enum VolumeWatcher {
    private static let clippingsFileName = "My Clippings.txt"
    private static let maxSearchDepth = 3
    private static let maxVisitedDirectories = 2000
    private static let maxSearchDuration: TimeInterval = 1
    private static let skippedSystemDirectoryNames: Set<String> = [
        ".spotlight-v100",
        ".trashes",
        ".fseventsd"
    ]

    private static let knownClippingsRelativePaths: [[String]] = [
        ["documents", clippingsFileName],
        ["Documents", clippingsFileName],
        [clippingsFileName]
    ]

    static func findClippingsFile(on volume: URL, fileManager: FileManager = .default) -> URL? {
        findClippingsFile(on: volume, fileManager: fileManager, now: Date.init)
    }

    static func findClippingsFile(
        on volume: URL,
        fileManager: FileManager,
        now: () -> Date
    ) -> URL? {
        for relativePathComponents in knownClippingsRelativePaths {
            let candidateURL = relativePathComponents.reduce(volume) { partialURL, component in
                partialURL.appendingPathComponent(component, isDirectory: false)
            }

            var isDirectory = ObjCBool(false)
            let exists = fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory)
            if exists && !isDirectory.boolValue {
                return candidateURL
            }
        }

        return findClippingsFileByFallbackSearch(on: volume, fileManager: fileManager, now: now)
    }

    private static func findClippingsFileByFallbackSearch(
        on volume: URL,
        fileManager: FileManager,
        now: () -> Date
    ) -> URL? {
        let deadline = now().addingTimeInterval(maxSearchDuration)
        var visitedDirectoryCount = 0
        var queue: [(url: URL, depth: Int)] = [(volume, 0)]
        var queueIndex = 0
        var firstNonDocumentsMatch: URL?
        let resourceKeys: Set<URLResourceKey> = [.isDirectoryKey, .nameKey]

        while queueIndex < queue.count {
            if now() >= deadline || visitedDirectoryCount >= maxVisitedDirectories {
                break
            }

            let current = queue[queueIndex]
            queueIndex += 1
            visitedDirectoryCount += 1

            guard let childURLs = try? fileManager.contentsOfDirectory(
                at: current.url,
                includingPropertiesForKeys: Array(resourceKeys),
                options: [.skipsPackageDescendants]
            ) else {
                continue
            }

            for childURL in childURLs.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let values = try? childURL.resourceValues(forKeys: resourceKeys) else {
                    continue
                }

                let name = values.name ?? childURL.lastPathComponent
                if values.isDirectory == true {
                    if current.depth < maxSearchDepth && !isSkippableDirectoryName(name) {
                        queue.append((childURL, current.depth + 1))
                    }
                    continue
                }

                if name.caseInsensitiveCompare(clippingsFileName) == .orderedSame {
                    if isUnderDocumentsDirectory(fileURL: childURL, volumeURL: volume) {
                        return childURL
                    }

                    if firstNonDocumentsMatch == nil {
                        firstNonDocumentsMatch = childURL
                    }
                }
            }
        }

        return firstNonDocumentsMatch
    }

    private static func isSkippableDirectoryName(_ name: String) -> Bool {
        let lowercasedName = name.lowercased()
        return lowercasedName.hasPrefix(".")
            || skippedSystemDirectoryNames.contains(lowercasedName)
            || lowercasedName.hasSuffix(".app")
    }

    private static func isUnderDocumentsDirectory(fileURL: URL, volumeURL: URL) -> Bool {
        let parentComponents = fileURL.deletingLastPathComponent().standardizedFileURL.pathComponents
        let volumeComponents = volumeURL.standardizedFileURL.pathComponents

        let componentsToCheck: ArraySlice<String>
        if parentComponents.starts(with: volumeComponents) {
            componentsToCheck = parentComponents.dropFirst(volumeComponents.count)
        } else {
            componentsToCheck = parentComponents[...]
        }

        return componentsToCheck.contains { component in
            component.caseInsensitiveCompare("documents") == .orderedSame
        }
    }
}

#if canImport(AppKit)
extension VolumeWatcher {
    private static let maxImportFileSizeBytes: Int64 = 20 * 1024 * 1024
    private static let maxImportWarningDetailCount = 20

    struct ImportPayload: Equatable {
        let newHighlightCount: Int
        let error: String?
        let skippedEntryCount: Int
        let warningMessages: [String]

        init(
            newHighlightCount: Int,
            error: String?,
            parseWarningCount _: Int? = nil,
            skippedEntryCount: Int,
            warningMessages: [String]
        ) {
            self.newHighlightCount = newHighlightCount
            self.error = error
            self.skippedEntryCount = skippedEntryCount
            self.warningMessages = warningMessages
        }

        var parseWarningCount: Int {
            warningMessages.count
        }
    }

    struct ImportStatus: Equatable {
        let message: String
        let isError: Bool
        let warningDetails: [String]
    }

    typealias FindClippingsFile = (URL) -> URL?
    typealias ImportFile = (URL) -> ImportPayload
    typealias PublishImportStatus = (ImportStatus) -> Void
    typealias DispatchWork = (@escaping () -> Void) -> Void

    final class MountListener {
        private let notificationCenter: NotificationCenter
        private let mountNotificationName: Notification.Name
        private let volumeURLUserInfoKey: String
        private let findClippingsFile: FindClippingsFile
        private let importFile: ImportFile
        private let publishImportStatus: PublishImportStatus
        private let dispatchWork: DispatchWork
        private let now: () -> Date
        private var observer: NSObjectProtocol?

        init(
            notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter,
            mountNotificationName: Notification.Name = NSWorkspace.didMountNotification,
            volumeURLUserInfoKey: String = NSWorkspace.volumeURLUserInfoKey,
            findClippingsFile: @escaping FindClippingsFile = { volumeURL in
                VolumeWatcher.findClippingsFile(on: volumeURL)
            },
            importFile: @escaping ImportFile,
            publishImportStatus: @escaping PublishImportStatus,
            dispatchWork: @escaping DispatchWork = { work in
                DispatchQueue.global(qos: .utility).async(execute: work)
            },
            now: @escaping () -> Date = Date.init
        ) {
            self.notificationCenter = notificationCenter
            self.mountNotificationName = mountNotificationName
            self.volumeURLUserInfoKey = volumeURLUserInfoKey
            self.findClippingsFile = findClippingsFile
            self.importFile = importFile
            self.publishImportStatus = publishImportStatus
            self.dispatchWork = dispatchWork
            self.now = now
        }

        deinit {
            stop()
        }

        func start() {
            guard observer == nil else {
                return
            }

            observer = notificationCenter.addObserver(
                forName: mountNotificationName,
                object: nil,
                queue: nil
            ) { [weak self] notification in
                self?.handleMountNotification(notification)
            }
        }

        func stop() {
            guard let observer else {
                return
            }

            notificationCenter.removeObserver(observer)
            self.observer = nil
        }

        private func handleMountNotification(_ notification: Notification) {
            guard let volumeURL = notification.userInfo?[volumeURLUserInfoKey] as? URL else {
                return
            }

            dispatchWork { [findClippingsFile, importFile, publishImportStatus, now] in
                VolumeWatcher.handleMountedVolume(
                    volumeURL,
                    findClippingsFile: findClippingsFile,
                    importFile: importFile,
                    publishImportStatus: publishImportStatus,
                    now: now
                )
            }
        }
    }

    static func handleMountedVolume(
        _ volumeURL: URL,
        findClippingsFile: FindClippingsFile = { findClippingsFile(on: $0) },
        importFile: ImportFile,
        publishImportStatus: PublishImportStatus,
        now: () -> Date = Date.init
    ) {
        guard let clippingsURL = findClippingsFile(volumeURL) else {
            return
        }

        if let sizeLimitError = importSizeLimitErrorMessage(for: clippingsURL, fileManager: .default) {
            let status = makeImportStatus(
                from: ImportPayload(
                    newHighlightCount: 0,
                    error: sizeLimitError,
                    parseWarningCount: 0,
                    skippedEntryCount: 0,
                    warningMessages: []
                ),
                now: now()
            )
            publishImportStatus(status)
            return
        }

        let importResult = importFile(clippingsURL)
        let status = makeImportStatus(from: importResult, now: now())
        publishImportStatus(status)
    }

    static func makeImportStatus(from result: ImportPayload, now: Date) -> ImportStatus {
        let warningDetails = cappedWarningDetails(from: result.warningMessages)
        if let error = result.error, !error.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ImportStatus(
                message: normalizedImportFailureMessage(error),
                isError: true,
                warningDetails: warningDetails
            )
        }

        guard result.newHighlightCount > 0 else {
            if result.skippedEntryCount > 0 {
                let warningSuffix = parseWarningSuffix(for: result.warningMessages)
                return ImportStatus(
                    message: "Last synced: \(importStatusDateFormatter.string(from: now)) - Import completed with warnings: 0 new highlights added, \(result.skippedEntryCount) \(skippedEntryNoun(for: result.skippedEntryCount)) skipped\(warningSuffix)",
                    isError: false,
                    warningDetails: warningDetails
                )
            }

            let warningSuffix = parseWarningSuffix(for: result.warningMessages)
            return ImportStatus(
                message: "Library up to date\(warningSuffix)",
                isError: false,
                warningDetails: warningDetails
            )
        }

        let timestamp = importStatusDateFormatter.string(from: now)
        let highlightNoun = result.newHighlightCount == 1 ? "highlight" : "highlights"
        if result.skippedEntryCount > 0 {
            let warningSuffix = parseWarningSuffix(for: result.warningMessages)
            return ImportStatus(
                message: "Last synced: \(timestamp) - Import completed with warnings: \(result.newHighlightCount) new \(highlightNoun) added, \(result.skippedEntryCount) \(skippedEntryNoun(for: result.skippedEntryCount)) skipped\(warningSuffix)",
                isError: false,
                warningDetails: warningDetails
            )
        }

        let warningSuffix = parseWarningSuffix(for: result.warningMessages)
        return ImportStatus(
            message: "Last synced: \(timestamp) - \(result.newHighlightCount) new \(highlightNoun) added\(warningSuffix)",
            isError: false,
            warningDetails: warningDetails
        )
    }

    private static let importStatusDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func normalizedImportFailureMessage(_ error: String) -> String {
        let trimmedError = error.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedError.isEmpty else {
            return "Import failed: unknown error."
        }

        if trimmedError.lowercased().hasPrefix("import failed:") {
            return trimmedError
        }

        return "Import failed: \(trimmedError)"
    }

    private static func parseWarningSuffix(for warningMessages: [String]) -> String {
        let parseWarningCount = warningMessages.count
        guard parseWarningCount > 0 else {
            return ""
        }
        let noun = parseWarningCount == 1 ? "parse warning" : "parse warnings"
        return " (\(parseWarningCount) \(noun))"
    }

    private static func cappedWarningDetails(from warningMessages: [String]) -> [String] {
        let normalizedMessages = warningMessages
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard normalizedMessages.count > maxImportWarningDetailCount else {
            return normalizedMessages
        }

        let visibleWarningCount = maxImportWarningDetailCount - 1
        let hiddenWarningCount = normalizedMessages.count - visibleWarningCount
        return Array(normalizedMessages.prefix(visibleWarningCount)) + ["… and \(hiddenWarningCount) more"]
    }

    private static func skippedEntryNoun(for skippedEntryCount: Int) -> String {
        skippedEntryCount == 1 ? "entry" : "entries"
    }

    private static func importSizeLimitErrorMessage(for clippingsURL: URL, fileManager: FileManager) -> String? {
        guard
            let attributes = try? fileManager.attributesOfItem(atPath: clippingsURL.path),
            let fileSizeNumber = attributes[.size] as? NSNumber
        else {
            return nil
        }

        let sizeInBytes = fileSizeNumber.int64Value
        guard sizeInBytes > maxImportFileSizeBytes else {
            return nil
        }

        let maxSizeInMegabytes = maxImportFileSizeBytes / (1024 * 1024)
        return "Import failed: clippings file is larger than \(maxSizeInMegabytes) MB."
    }
}
#endif

#if canImport(AppKit) && canImport(GRDB)
extension VolumeWatcher.MountListener {
    static func live(
        publishImportStatus: @escaping VolumeWatcher.PublishImportStatus,
        applyLibrarySnapshot: @escaping (LibrarySnapshot) -> Void,
        notificationCenter: NotificationCenter = NSWorkspace.shared.notificationCenter
    ) -> VolumeWatcher.MountListener {
        VolumeWatcher.MountListener(
            notificationCenter: notificationCenter,
            importFile: { clippingsURL in
                let result = ImportCoordinator.live.importFile(at: clippingsURL)
                if let librarySnapshot = result.librarySnapshot {
                    applyLibrarySnapshot(librarySnapshot)
                }
                return VolumeWatcher.ImportPayload(
                    newHighlightCount: result.newHighlightCount,
                    error: result.error,
                    skippedEntryCount: result.skippedEntryCount,
                    warningMessages: result.warningMessages
                )
            },
            publishImportStatus: publishImportStatus
        )
    }
}
#endif
