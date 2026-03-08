import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t62_main failed: \(message)\n", stderr)
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

private func makeHighlight(id: UUID = UUID(), quoteText: String = "Quote") -> Highlight {
    Highlight(
        id: id,
        bookId: UUID(),
        quoteText: quoteText,
        bookTitle: "Book",
        author: "Author",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil
    )
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T62-\(UUID().uuidString)"
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

private func makeGenerator(
    appSupportDirectory: URL,
    retainedGeneratedFileCount: Int,
    protectedGeneratedWallpapersProvider: @escaping () -> [URL]
) -> WallpaperGenerator {
    WallpaperGenerator(
        fileManager: .default,
        appSupportDirectoryProvider: { appSupportDirectory },
        mainScreenPixelSizeProvider: { CGSize(width: 48, height: 32) },
        mainScreenScaleProvider: { 1.0 },
        backgroundImageLoader: BackgroundImageLoader(
            fileManager: .default,
            loadImage: { _ in nil },
            logger: { _ in }
        ),
        retainedGeneratedFileCount: retainedGeneratedFileCount,
        protectedGeneratedWallpapersProvider: protectedGeneratedWallpapersProvider
    )
}

private func setModificationDate(_ date: Date, for fileURL: URL) {
    do {
        try FileManager.default.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: fileURL.path
        )
    } catch {
        fail("Unable to set modification date for \(fileURL.path): \(error)")
    }
}

private func testStoredGeneratedWallpapersPruneMissingFiles() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t62-defaults")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let existingURL = tempDirectory.appendingPathComponent("existing.png", isDirectory: false)
    let missingURL = tempDirectory.appendingPathComponent("missing.png", isDirectory: false)

    FileManager.default.createFile(atPath: existingURL.path, contents: Data("ok".utf8))

    defaults.storeReusableGeneratedWallpapers([
        StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: existingURL),
        StoredGeneratedWallpaper(targetIdentifier: "display-b", fileURL: missingURL)
    ])

    let loadedWallpapers = defaults.loadReusableGeneratedWallpapers()
    expectEqual(loadedWallpapers.count, 1, "Expected missing stored wallpaper entry to be pruned")
    expectEqual(loadedWallpapers.first?.targetIdentifier, "display-a", "Expected existing target to remain")
    expectEqual(
        loadedWallpapers.first?.fileURL.standardizedFileURL,
        existingURL.standardizedFileURL,
        "Expected existing file URL to remain"
    )

    let reloadedWallpapers = defaults.loadReusableGeneratedWallpapers()
    expectEqual(reloadedWallpapers, loadedWallpapers, "Expected pruned wallpaper storage to remain stable")
}

private func testCleanupPreservesProtectedAppliedWallpaper() {
    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t62-protected")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    var protectedURLs: [URL] = []
    let generator = makeGenerator(
        appSupportDirectory: tempDirectory,
        retainedGeneratedFileCount: 1,
        protectedGeneratedWallpapersProvider: { protectedURLs }
    )

    let target = WallpaperGenerator.RenderTarget(identifier: "main", pixelWidth: 48, pixelHeight: 32)

    let first = generator.generateWallpapers(
        highlight: makeHighlight(quoteText: "First"),
        backgroundURL: nil,
        targets: [target],
        rotationID: "rotation-1"
    )
    guard let firstURL = first.first?.fileURL else {
        fail("Expected first generated wallpaper URL")
    }
    setModificationDate(Date(timeIntervalSince1970: 1), for: firstURL)
    protectedURLs = [firstURL]

    let second = generator.generateWallpapers(
        highlight: makeHighlight(quoteText: "Second"),
        backgroundURL: nil,
        targets: [target],
        rotationID: "rotation-2"
    )
    guard let secondURL = second.first?.fileURL else {
        fail("Expected second generated wallpaper URL")
    }
    setModificationDate(Date(timeIntervalSince1970: 2), for: secondURL)

    let third = generator.generateWallpapers(
        highlight: makeHighlight(quoteText: "Third"),
        backgroundURL: nil,
        targets: [target],
        rotationID: "rotation-3"
    )
    guard let thirdURL = third.first?.fileURL else {
        fail("Expected third generated wallpaper URL")
    }
    setModificationDate(Date(timeIntervalSince1970: 3), for: thirdURL)

    let fourth = generator.generateWallpapers(
        highlight: makeHighlight(quoteText: "Fourth"),
        backgroundURL: nil,
        targets: [target],
        rotationID: "rotation-4"
    )
    guard let fourthURL = fourth.first?.fileURL else {
        fail("Expected fourth generated wallpaper URL")
    }

    expect(FileManager.default.fileExists(atPath: firstURL.path), "Expected protected wallpaper to survive cleanup")
    expect(!FileManager.default.fileExists(atPath: secondURL.path), "Expected stale unprotected wallpaper to be deleted")
    expect(FileManager.default.fileExists(atPath: fourthURL.path), "Expected newest wallpaper to remain after cleanup")
}

private func testCleanupProtectsEntireCurrentGenerationBatch() {
    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t62-batch")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let generator = makeGenerator(
        appSupportDirectory: tempDirectory,
        retainedGeneratedFileCount: 1,
        protectedGeneratedWallpapersProvider: { [] }
    )

    let generated = generator.generateWallpapers(
        highlight: makeHighlight(quoteText: "Batch"),
        backgroundURL: nil,
        targets: [
            WallpaperGenerator.RenderTarget(identifier: "display-a", pixelWidth: 48, pixelHeight: 32),
            WallpaperGenerator.RenderTarget(identifier: "display-b", pixelWidth: 48, pixelHeight: 32)
        ],
        rotationID: "rotation-batch"
    )

    expectEqual(generated.count, 2, "Expected both target wallpapers to be generated")
    for wallpaper in generated {
        expect(
            FileManager.default.fileExists(atPath: wallpaper.fileURL.path),
            "Expected cleanup to preserve every file in the current generation batch"
        )
    }
}

private func testCleanupProtectsCanonicalizedPersistedWallpaperPaths() {
    let fileManager = FileManager.default
    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t62-canonical")
    defer { try? fileManager.removeItem(at: tempDirectory) }

    let realAppSupportDirectory = tempDirectory.appendingPathComponent("real", isDirectory: true)
    let symlinkedAppSupportDirectory = tempDirectory.appendingPathComponent("symlinked", isDirectory: true)
    do {
        try fileManager.createDirectory(at: realAppSupportDirectory, withIntermediateDirectories: true)
        try fileManager.createSymbolicLink(
            atPath: symlinkedAppSupportDirectory.path,
            withDestinationPath: realAppSupportDirectory.path
        )
    } catch {
        fail("Unable to configure symlinked app support directory: \(error)")
    }

    var protectedURLs: [URL] = []
    let generator = makeGenerator(
        appSupportDirectory: realAppSupportDirectory,
        retainedGeneratedFileCount: 1,
        protectedGeneratedWallpapersProvider: { protectedURLs }
    )

    let target = WallpaperGenerator.RenderTarget(identifier: "main", pixelWidth: 48, pixelHeight: 32)
    let first = generator.generateWallpapers(
        highlight: makeHighlight(quoteText: "First canonical"),
        backgroundURL: nil,
        targets: [target],
        rotationID: "canonical-1"
    )
    guard let firstURL = first.first?.fileURL else {
        fail("Expected first canonical generated wallpaper URL")
    }
    protectedURLs = [
        URL(fileURLWithPath: firstURL.path.replacingOccurrences(
            of: realAppSupportDirectory.path,
            with: symlinkedAppSupportDirectory.path
        ))
    ]

    _ = generator.generateWallpapers(
        highlight: makeHighlight(quoteText: "Second canonical"),
        backgroundURL: nil,
        targets: [target],
        rotationID: "canonical-2"
    )
    _ = generator.generateWallpapers(
        highlight: makeHighlight(quoteText: "Third canonical"),
        backgroundURL: nil,
        targets: [target],
        rotationID: "canonical-3"
    )

    expect(
        fileManager.fileExists(atPath: firstURL.path),
        "Expected canonicalized protected wallpaper path to survive cleanup"
    )
}

@MainActor
private func testAppStateStoresReusableWallpaperOnlyAfterSuccessfulSingleApply() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t62-single")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let successURL = tempDirectory.appendingPathComponent("success.png", isDirectory: false)
    FileManager.default.createFile(atPath: successURL.path, contents: Data("success".utf8))

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { makeHighlight(quoteText: "Persist me") },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in successURL },
        setWallpaper: { _ in },
        storeReusableGeneratedWallpapers: { wallpapers in
            defaults.storeReusableGeneratedWallpapers(
                wallpapers.map { wallpaper in
                    StoredGeneratedWallpaper(
                        targetIdentifier: wallpaper.targetIdentifier,
                        fileURL: wallpaper.fileURL
                    )
                }
            )
        },
        markHighlightShown: { _ in }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(outcome, .success, "Expected single-wallpaper rotation to succeed")

    let storedWallpapers = defaults.loadReusableGeneratedWallpapers(
        fileManager: FileManager.default
    )
    expectEqual(storedWallpapers.count, 1, "Expected successful single-wallpaper apply to persist one reusable wallpaper")
    expectEqual(
        storedWallpapers.first?.targetIdentifier,
        StoredGeneratedWallpaper.allScreensTargetIdentifier,
        "Expected single-wallpaper apply to persist the all-screens target identifier"
    )
    expectEqual(
        storedWallpapers.first?.fileURL.standardizedFileURL,
        successURL.standardizedFileURL,
        "Expected single-wallpaper apply to persist the generated wallpaper file URL"
    )

    defaults.storeReusableGeneratedWallpapers([])
    let failureURL = tempDirectory.appendingPathComponent("failed.png", isDirectory: false)
    FileManager.default.createFile(atPath: failureURL.path, contents: Data("failure".utf8))
    let failingAppState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { makeHighlight(quoteText: "Do not persist") },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in failureURL },
        setWallpaper: { _ in
            struct TestError: Error {}
            throw TestError()
        },
        storeReusableGeneratedWallpapers: { wallpapers in
            defaults.storeReusableGeneratedWallpapers(
                wallpapers.map { wallpaper in
                    StoredGeneratedWallpaper(
                        targetIdentifier: wallpaper.targetIdentifier,
                        fileURL: wallpaper.fileURL
                    )
                }
            )
        },
        markHighlightShown: { _ in }
    )

    let failureOutcome = failingAppState.rotateWallpaperWithOutcome()
    expectEqual(
        failureOutcome,
        .wallpaperApplyFailure(.applyError),
        "Expected failed single-wallpaper apply to report apply error"
    )
    expectEqual(
        defaults.loadReusableGeneratedWallpapers().count,
        0,
        "Expected failed single-wallpaper apply not to persist reusable wallpaper storage"
    )
}

@MainActor
private func testAppStateStoresTargetedReusableWallpapersAfterSuccessfulApply() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let tempDirectory = makeTemporaryDirectory(prefix: "kindlewall-t62-appstate")
    defer { try? FileManager.default.removeItem(at: tempDirectory) }

    let firstURL = tempDirectory.appendingPathComponent("display-a.png", isDirectory: false)
    let secondURL = tempDirectory.appendingPathComponent("display-b.png", isDirectory: false)
    FileManager.default.createFile(atPath: firstURL.path, contents: Data("a".utf8))
    FileManager.default.createFile(atPath: secondURL.path, contents: Data("b".utf8))

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { makeHighlight(quoteText: "Persist targets") },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            fail("Expected targeted wallpaper path to be used")
        },
        setWallpaper: { _ in
            fail("Expected targeted wallpaper setter path to be used")
        },
        prepareWallpaperRotation: {
            AppState.WallpaperRotationPlan(
                targets: [
                    AppState.WallpaperTarget(identifier: "display-a", pixelWidth: 48, pixelHeight: 32, backingScaleFactor: 1.0),
                    AppState.WallpaperTarget(identifier: "display-b", pixelWidth: 48, pixelHeight: 32, backingScaleFactor: 1.0)
                ],
                applyGeneratedWallpapers: { _ in }
            )
        },
        generateWallpapers: { _, _, _ in
            [
                AppState.GeneratedWallpaper(targetIdentifier: "display-a", fileURL: firstURL),
                AppState.GeneratedWallpaper(targetIdentifier: "display-b", fileURL: secondURL)
            ]
        },
        storeReusableGeneratedWallpapers: { wallpapers in
            defaults.storeReusableGeneratedWallpapers(
                wallpapers.map { wallpaper in
                    StoredGeneratedWallpaper(
                        targetIdentifier: wallpaper.targetIdentifier,
                        fileURL: wallpaper.fileURL
                    )
                }
            )
        },
        markHighlightShown: { _ in }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(outcome, .success, "Expected targeted wallpaper rotation to succeed")

    let storedWallpapers = defaults.loadReusableGeneratedWallpapers()
    expectEqual(storedWallpapers.count, 2, "Expected targeted rotation to persist both wallpaper assignments")
    expectEqual(storedWallpapers[0].targetIdentifier, "display-a", "Expected first targeted wallpaper identifier to persist")
    expectEqual(storedWallpapers[0].fileURL.standardizedFileURL, firstURL.standardizedFileURL, "Expected first targeted wallpaper file URL to persist")
    expectEqual(storedWallpapers[1].targetIdentifier, "display-b", "Expected second targeted wallpaper identifier to persist")
    expectEqual(storedWallpapers[1].fileURL.standardizedFileURL, secondURL.standardizedFileURL, "Expected second targeted wallpaper file URL to persist")
}

testStoredGeneratedWallpapersPruneMissingFiles()
testCleanupPreservesProtectedAppliedWallpaper()
testCleanupProtectsEntireCurrentGenerationBatch()
testCleanupProtectsCanonicalizedPersistedWallpaperPaths()

await MainActor.run {
    testAppStateStoresReusableWallpaperOnlyAfterSuccessfulSingleApply()
    testAppStateStoresTargetedReusableWallpapersAfterSuccessfulApply()
}

print("verify_t62_main passed")
