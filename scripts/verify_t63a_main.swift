import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t63a_main failed: \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fail("\(message). Expected \(expected), got \(actual)")
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T63a-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fail("Unable to create isolated UserDefaults suite")
    }

    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "__verifySuiteName")
    return defaults
}

private func clearDefaults(_ defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: "__verifySuiteName"), !suiteName.isEmpty else {
        return
    }

    defaults.removePersistentDomain(forName: suiteName)
}

private func makeTemporaryDirectory(prefix: String) -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        fail("Unable to create temporary directory: \(error)")
    }
    return directory
}

private func writeFile(at url: URL, contents: String = "ok") {
    let parentDirectory = url.deletingLastPathComponent()
    do {
        try FileManager.default.createDirectory(at: parentDirectory, withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: url, options: .atomic)
    } catch {
        fail("Unable to write test file at \(url.path): \(error)")
    }
}

private func writeHistoryPlist(
    root: [String: Any],
    format: PropertyListSerialization.PropertyListFormat,
    to url: URL
) {
    do {
        let data = try PropertyListSerialization.data(
            fromPropertyList: root,
            format: format,
            options: 0
        )
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    } catch {
        fail("Unable to write history plist at \(url.path): \(error)")
    }
}

private func loadHistoryPlist(
    from url: URL
) -> (root: [String: Any], format: PropertyListSerialization.PropertyListFormat) {
    do {
        let data = try Data(contentsOf: url)
        var format = PropertyListSerialization.PropertyListFormat.binary
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: &format)
        guard let root = plist as? [String: Any] else {
            fail("Expected history plist root dictionary")
        }
        return (root, format)
    } catch {
        fail("Unable to load history plist at \(url.path): \(error)")
    }
}

private func relativePaths(in root: [String: Any]) -> [String] {
    guard let choices = root["Choices"] as? [[String: Any]] else {
        fail("Expected Choices array in history plist")
    }

    return choices.flatMap { choice -> [String] in
        guard let files = choice["Files"] as? [[String: Any]] else {
            return []
        }
        return files.compactMap { $0["relative"] as? String }
    }
}

private func choices(in root: [String: Any]) -> [[String: Any]] {
    guard let choices = root["Choices"] as? [[String: Any]] else {
        fail("Expected Choices array in history plist")
    }
    return choices
}

private func makeHistoryRoot(choices: [[String: Any]]) -> [String: Any] {
    [
        "DesktopPictures": [],
        "SchemaVersion": 1,
        "Choices": choices
    ]
}

private func makeFileEntry(relativePath: String, tag: String) -> [String: Any] {
    [
        "relative": relativePath,
        "tag": tag
    ]
}

private func testPrunerRemovesMissingKindleWallPathsAndPreservesUnrelatedEntries() {
    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t63a-prune")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let indexPlistURL = tempDirectory.appendingPathComponent("Index.plist", isDirectory: false)
    let kindleWallDirectory = tempDirectory.appendingPathComponent("KindleWall", isDirectory: true)
    let unrelatedDirectory = tempDirectory.appendingPathComponent("OtherApp", isDirectory: true)

    let existingKindlePath = kindleWallDirectory
        .appendingPathComponent("generated-wallpapers/existing.png", isDirectory: false)
    let staleKindlePathA = kindleWallDirectory
        .appendingPathComponent("generated-wallpapers/stale-a.png", isDirectory: false)
    let staleKindlePathB = kindleWallDirectory
        .appendingPathComponent("generated-wallpapers/stale-b.png", isDirectory: false)
    let unrelatedMissingPath = unrelatedDirectory
        .appendingPathComponent("missing.png", isDirectory: false)
    let unrelatedExistingPath = unrelatedDirectory
        .appendingPathComponent("existing.png", isDirectory: false)

    writeFile(at: existingKindlePath)
    writeFile(at: unrelatedExistingPath)

    writeHistoryPlist(
        root: makeHistoryRoot(choices: [
            [
                "Display": "main",
                "Files": [
                    makeFileEntry(relativePath: staleKindlePathA.path, tag: "stale-a"),
                    makeFileEntry(relativePath: existingKindlePath.path, tag: "existing-kindle"),
                    makeFileEntry(relativePath: unrelatedMissingPath.path, tag: "unrelated-missing")
                ]
            ],
            [
                "Display": "secondary",
                "Files": [
                    makeFileEntry(relativePath: staleKindlePathB.path, tag: "stale-b")
                ]
            ],
            [
                "Display": "third",
                "Files": [
                    makeFileEntry(relativePath: unrelatedExistingPath.path, tag: "unrelated-existing")
                ]
            ]
        ]),
        format: .binary,
        to: indexPlistURL
    )

    let pruner = WallpaperHistoryPruner(
        fileManager: .default,
        indexPlistURL: indexPlistURL
    )
    pruner.prune(pathsToPrune: [staleKindlePathA.path, staleKindlePathB.path])

    let history = loadHistoryPlist(from: indexPlistURL)
    expectEqual(history.format, .binary, "Expected pruning to preserve the original plist format")

    let paths = relativePaths(in: history.root)
    expect(!paths.contains(staleKindlePathA.path), "Expected first stale KindleWall path to be removed")
    expect(!paths.contains(staleKindlePathB.path), "Expected second stale KindleWall path to be removed")
    expect(paths.contains(existingKindlePath.path), "Expected existing KindleWall path to remain")
    expect(paths.contains(unrelatedMissingPath.path), "Expected unrelated non-KindleWall path to remain untouched")
    expect(paths.contains(unrelatedExistingPath.path), "Expected unrelated existing path to remain untouched")

    let updatedChoices = choices(in: history.root)
    expect(
        updatedChoices[1]["Files"] == nil,
        "Expected empty Files arrays to be cleaned up after pruning"
    )
}

private func testPrunerPreservesExistingPathsEvenWhenRequestedForPrune() {
    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t63a-existing")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let indexPlistURL = tempDirectory.appendingPathComponent("Index.plist", isDirectory: false)
    let existingKindlePath = tempDirectory
        .appendingPathComponent("KindleWall/generated-wallpapers/existing.png", isDirectory: false)
    writeFile(at: existingKindlePath)

    writeHistoryPlist(
        root: makeHistoryRoot(choices: [
            [
                "Files": [
                    makeFileEntry(relativePath: existingKindlePath.path, tag: "existing")
                ]
            ]
        ]),
        format: .xml,
        to: indexPlistURL
    )

    let pruner = WallpaperHistoryPruner(
        fileManager: .default,
        indexPlistURL: indexPlistURL
    )
    pruner.prune(pathsToPrune: [existingKindlePath.path])

    let history = loadHistoryPlist(from: indexPlistURL)
    expectEqual(history.format, .xml, "Expected XML plist format to remain unchanged")
    expect(
        relativePaths(in: history.root).contains(existingKindlePath.path),
        "Expected prune request to preserve paths that still exist on disk"
    )
}

private func testMigrationRunsOnceAndSecondRunSkips() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t63a-run-once")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let indexPlistURL = tempDirectory.appendingPathComponent("Index.plist", isDirectory: false)
    let kindleWallDirectory = tempDirectory.appendingPathComponent("KindleWall", isDirectory: true)

    let staleKindlePath = kindleWallDirectory
        .appendingPathComponent("generated-wallpapers/stale-first-run.png", isDirectory: false)
    let skippedOnSecondRunPath = kindleWallDirectory
        .appendingPathComponent("generated-wallpapers/stale-second-run.png", isDirectory: false)
    let existingKindlePath = kindleWallDirectory
        .appendingPathComponent("generated-wallpapers/existing.png", isDirectory: false)
    writeFile(at: existingKindlePath)

    writeHistoryPlist(
        root: makeHistoryRoot(choices: [
            [
                "Files": [
                    makeFileEntry(relativePath: staleKindlePath.path, tag: "first"),
                    makeFileEntry(relativePath: existingKindlePath.path, tag: "existing")
                ]
            ]
        ]),
        format: .binary,
        to: indexPlistURL
    )

    KindleWallApp.testPruneStaleWallpaperHistoryIfNeeded(
        userDefaults: defaults,
        indexPlistURL: indexPlistURL,
        kindleWallDirectoryURL: kindleWallDirectory
    )

    expect(defaults.didPruneStaleWallpaperHistory, "Expected first run to set the migration completion flag")
    expect(
        !relativePaths(in: loadHistoryPlist(from: indexPlistURL).root).contains(staleKindlePath.path),
        "Expected first run to prune stale KindleWall history entries"
    )

    writeHistoryPlist(
        root: makeHistoryRoot(choices: [
            [
                "Files": [
                    makeFileEntry(relativePath: skippedOnSecondRunPath.path, tag: "second"),
                    makeFileEntry(relativePath: existingKindlePath.path, tag: "existing")
                ]
            ]
        ]),
        format: .binary,
        to: indexPlistURL
    )

    KindleWallApp.testPruneStaleWallpaperHistoryIfNeeded(
        userDefaults: defaults,
        indexPlistURL: indexPlistURL,
        kindleWallDirectoryURL: kindleWallDirectory
    )

    expect(
        relativePaths(in: loadHistoryPlist(from: indexPlistURL).root).contains(skippedOnSecondRunPath.path),
        "Expected second run to skip pruning after the flag has been set"
    )
}

private func testMalformedPlistStillSetsFlag() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t63a-malformed")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let indexPlistURL = tempDirectory.appendingPathComponent("Index.plist", isDirectory: false)
    let originalData = Data("not a plist".utf8)
    do {
        try originalData.write(to: indexPlistURL, options: .atomic)
    } catch {
        fail("Unable to write malformed plist fixture: \(error)")
    }

    KindleWallApp.testPruneStaleWallpaperHistoryIfNeeded(
        userDefaults: defaults,
        indexPlistURL: indexPlistURL,
        kindleWallDirectoryURL: tempDirectory.appendingPathComponent("KindleWall", isDirectory: true)
    )

    expect(defaults.didPruneStaleWallpaperHistory, "Expected malformed plist run to still set the completion flag")

    do {
        let persistedData = try Data(contentsOf: indexPlistURL)
        expectEqual(persistedData, originalData, "Expected malformed plist contents to remain unchanged")
    } catch {
        fail("Unable to reload malformed plist fixture: \(error)")
    }
}

private func testMissingPlistStillSetsFlag() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t63a-missing")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let indexPlistURL = tempDirectory
        .appendingPathComponent("Store", isDirectory: true)
        .appendingPathComponent("Index.plist", isDirectory: false)

    KindleWallApp.testPruneStaleWallpaperHistoryIfNeeded(
        userDefaults: defaults,
        indexPlistURL: indexPlistURL,
        kindleWallDirectoryURL: tempDirectory.appendingPathComponent("KindleWall", isDirectory: true)
    )

    expect(defaults.didPruneStaleWallpaperHistory, "Expected missing plist run to still set the completion flag")
    expect(
        !FileManager.default.fileExists(atPath: indexPlistURL.path),
        "Expected missing plist run to remain a no-op"
    )
}

testPrunerRemovesMissingKindleWallPathsAndPreservesUnrelatedEntries()
testPrunerPreservesExistingPathsEvenWhenRequestedForPrune()
testMigrationRunsOnceAndSecondRunSkips()
testMalformedPlistStillSetsFlag()
testMissingPlistStillSetsFlag()

print("verify_t63a_main passed")
