import Foundation

struct WallpaperHistoryPruner {
    private let fileManager: FileManager
    private let indexPlistURL: URL

    init(
        fileManager: FileManager = .default,
        indexPlistURL: URL? = nil
    ) {
        self.fileManager = fileManager
        if let indexPlistURL {
            self.indexPlistURL = indexPlistURL
        } else {
            self.indexPlistURL = fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent("Library", isDirectory: true)
                .appendingPathComponent("Application Support", isDirectory: true)
                .appendingPathComponent("com.apple.wallpaper", isDirectory: true)
                .appendingPathComponent("Store", isDirectory: true)
                .appendingPathComponent("Index.plist", isDirectory: false)
        }
    }

    func staleKindleWallPNGPaths(
        kindleWallDirectoryURL: URL = AppSupportPaths.kindleWallDirectory()
    ) -> Set<String> {
        guard let history = loadHistory() else {
            return []
        }

        let kindleWallDirectoryPath = normalizedAbsolutePath(for: kindleWallDirectoryURL)
        guard !kindleWallDirectoryPath.isEmpty else {
            return []
        }

        return Set(history.relativePaths.filter { path in
            guard
                let normalizedPath = normalizedAbsolutePath(forPath: path),
                normalizedPath.hasPrefix(kindleWallDirectoryPath + "/"),
                URL(fileURLWithPath: normalizedPath).pathExtension.lowercased() == "png"
            else {
                return false
            }

            return !fileManager.fileExists(atPath: normalizedPath)
        })
    }

    func prune(pathsToPrune: Set<String>) {
        guard !pathsToPrune.isEmpty else {
            return
        }

        guard let history = loadHistory() else {
            return
        }

        let rawPathsToPrune = Set(pathsToPrune.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
        let normalizedPathsToPrune = Set(pathsToPrune.compactMap(normalizedAbsolutePath(forPath:)))
        guard !rawPathsToPrune.isEmpty || !normalizedPathsToPrune.isEmpty else {
            return
        }

        let updatedChoices = history.choices.map { choice -> [String: Any] in
            guard let rawFiles = choice["Files"] else {
                return choice
            }
            let files = rawFiles as? [[String: Any]] ?? []

            var updatedFiles: [[String: Any]] = []
            updatedFiles.reserveCapacity(files.count)

            for file in files {
                guard let relativePath = file["relative"] as? String else {
                    updatedFiles.append(file)
                    continue
                }

                let trimmedPath = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedPath = normalizedAbsolutePath(forPath: relativePath)
                let shouldPrune =
                    rawPathsToPrune.contains(trimmedPath) ||
                    (normalizedPath.map(normalizedPathsToPrune.contains) ?? false)

                guard shouldPrune else {
                    updatedFiles.append(file)
                    continue
                }

                if let normalizedPath, fileManager.fileExists(atPath: normalizedPath) {
                    updatedFiles.append(file)
                }
            }

            var updatedChoice = choice
            if updatedFiles.isEmpty {
                updatedChoice.removeValue(forKey: "Files")
            } else {
                updatedChoice["Files"] = updatedFiles
            }
            return updatedChoice
        }

        var updatedRoot = history.root
        updatedRoot["Choices"] = updatedChoices

        guard
            let plistData = try? PropertyListSerialization.data(
                fromPropertyList: updatedRoot,
                format: history.format,
                options: 0
            )
        else {
            return
        }

        try? plistData.write(to: indexPlistURL, options: .atomic)
    }

    private func loadHistory() -> (root: [String: Any], choices: [[String: Any]], relativePaths: [String], format: PropertyListSerialization.PropertyListFormat)? {
        guard
            let data = try? Data(contentsOf: indexPlistURL)
        else {
            return nil
        }

        var format = PropertyListSerialization.PropertyListFormat.binary
        guard
            let propertyList = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: &format
            ),
            let root = propertyList as? [String: Any],
            let choices = root["Choices"] as? [[String: Any]]
        else {
            return nil
        }

        var relativePaths: [String] = []
        relativePaths.reserveCapacity(choices.count)

        for choice in choices {
            guard let rawFiles = choice["Files"] else {
                continue
            }
            guard let files = rawFiles as? [[String: Any]] else {
                return nil
            }

            for file in files {
                if let relativePath = file["relative"] as? String {
                    relativePaths.append(relativePath)
                }
            }
        }

        return (root, choices, relativePaths, format)
    }

    private func normalizedAbsolutePath(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func normalizedAbsolutePath(forPath path: String) -> String? {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPath.isEmpty, NSString(string: trimmedPath).isAbsolutePath else {
            return nil
        }

        return URL(fileURLWithPath: trimmedPath).standardizedFileURL.path
    }
}
