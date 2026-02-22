import Foundation

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
