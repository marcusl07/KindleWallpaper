import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t64_main failed: \(message)\n", stderr)
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

private func makeResolvedScreen(
    screen: String,
    identifier: String
) -> WallpaperSetter.ResolvedScreen<String> {
    WallpaperSetter.ResolvedScreen(
        screen: screen,
        identifier: identifier,
        pixelWidth: 1,
        pixelHeight: 1
    )
}

private func makeWallpaper(directory: URL, name: String) -> URL {
    let fileURL = directory.appendingPathComponent(name, isDirectory: false)
    FileManager.default.createFile(atPath: fileURL.path, contents: Data(name.utf8))
    return fileURL
}

private func testFullRestoreForAllScreensWallpaper() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-all")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "all.png")
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a"),
        makeResolvedScreen(screen: "screen-b", identifier: "display-b")
    ]

    var applied: [(String, URL)] = []
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(
                targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                fileURL: wallpaperURL
            )
        ],
        resolvedScreens: screens,
        setDesktopImage: { url, screen in
            applied.append((screen, url))
        }
    )

    expectEqual(outcome, .fullRestore, "Expected all-screens wallpaper to report a full restore")
    expectEqual(outcome.didRestore, true, "Expected full restore to report that wallpapers were restored")
    expectEqual(applied.count, 2, "Expected all connected screens to receive the restored wallpaper")
    expectEqual(applied[0].0, "screen-a", "Expected first connected screen to be restored")
    expectEqual(applied[1].0, "screen-b", "Expected second connected screen to be restored")
}

private func testFullRestoreForTargetedScreens() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-targeted")
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = makeWallpaper(directory: directory, name: "display-a.png")
    let secondURL = makeWallpaper(directory: directory, name: "display-b.png")
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a"),
        makeResolvedScreen(screen: "screen-b", identifier: "display-b")
    ]

    var applied: [(String, URL)] = []
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: firstURL),
            StoredGeneratedWallpaper(targetIdentifier: "display-b", fileURL: secondURL)
        ],
        resolvedScreens: screens,
        setDesktopImage: { url, screen in
            applied.append((screen, url))
        }
    )

    expectEqual(outcome, .fullRestore, "Expected matching targeted wallpapers to report a full restore")
    expectEqual(applied.count, 2, "Expected all stored targeted wallpapers to be applied")
    expectEqual(applied[0].1.standardizedFileURL, firstURL.standardizedFileURL, "Expected first target to keep its stored wallpaper")
    expectEqual(applied[1].1.standardizedFileURL, secondURL.standardizedFileURL, "Expected second target to keep its stored wallpaper")
}

private func testPartialRestoreWhenTopologyIsReduced() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-partial")
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = makeWallpaper(directory: directory, name: "display-a.png")
    let secondURL = makeWallpaper(directory: directory, name: "display-b.png")
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a")
    ]

    var applied: [(String, URL)] = []
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: firstURL),
            StoredGeneratedWallpaper(targetIdentifier: "display-b", fileURL: secondURL)
        ],
        resolvedScreens: screens,
        setDesktopImage: { url, screen in
            applied.append((screen, url))
        }
    )

    expectEqual(outcome, .partialRestore, "Expected reduced topology restore to report partial restore")
    expectEqual(outcome.didRestore, true, "Expected partial restore to report that some wallpapers were restored")
    expectEqual(applied.count, 1, "Expected only connected matching screens to receive wallpapers")
    expectEqual(applied[0].0, "screen-a", "Expected matching connected screen to keep its wallpaper")
}

private func testNoStoredWallpaperOutcome() {
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a")
    ]

    var applyCallCount = 0
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [],
        resolvedScreens: screens,
        setDesktopImage: { _, _ in
            applyCallCount += 1
        }
    )

    expectEqual(outcome, .noStoredWallpapers, "Expected empty stored wallpaper state to be explicit")
    expectEqual(outcome.didRestore, false, "Expected no stored wallpapers to report no restore work")
    expectEqual(applyCallCount, 0, "Expected empty storage to skip wallpaper application")
}

private func testNoConnectedScreensOutcome() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-noscreens")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "all.png")
    var applyCallCount = 0
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(
                targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                fileURL: wallpaperURL
            )
        ],
        resolvedScreens: [WallpaperSetter.ResolvedScreen<String>](),
        setDesktopImage: { (_: URL, _: String) in
            applyCallCount += 1
        }
    )

    expectEqual(outcome, .noConnectedScreens, "Expected explicit no-screen restore outcome")
    expectEqual(outcome.didRestore, false, "Expected no connected screens to report no restore work")
    expectEqual(applyCallCount, 0, "Expected missing connected screens to skip wallpaper application")
}

private enum TestError: Error {
    case applyFailed
}

private func testApplyFailureOutcome() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-failure")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "all.png")
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a")
    ]

    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(
                targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                fileURL: wallpaperURL
            )
        ],
        resolvedScreens: screens,
        setDesktopImage: { _, _ in
            throw TestError.applyFailed
        }
    )

    expectEqual(outcome, .applyFailure, "Expected thrown apply errors to map to applyFailure")
    expectEqual(outcome.didRestore, false, "Expected apply failure to report no completed restore")
}

@MainActor
private func testAppStateReapplyForwardsStructuredOutcome() {
    var reapplyCallCount = 0
    var markHighlightShownCount = 0

    let appState = AppState(
        pickNextHighlight: {
            fail("Expected wake restore not to request a new highlight")
        },
        generateWallpaper: { _, _ in
            fail("Expected wake restore not to generate a new wallpaper")
        },
        setWallpaper: { _ in
            fail("Expected wake restore not to use the rotation apply path")
        },
        reapplyStoredWallpaper: {
            reapplyCallCount += 1
            return .partialRestore
        },
        markHighlightShown: { _ in
            markHighlightShownCount += 1
        }
    )

    let outcome = appState.reapplyStoredWallpaperIfAvailable()
    expectEqual(outcome, .partialRestore, "Expected AppState wake restore to forward the structured outcome")
    expectEqual(reapplyCallCount, 1, "Expected AppState wake restore to delegate exactly once")
    expectEqual(markHighlightShownCount, 0, "Expected wake restore not to advance rotation state")
}

testFullRestoreForAllScreensWallpaper()
testFullRestoreForTargetedScreens()
testPartialRestoreWhenTopologyIsReduced()
testNoStoredWallpaperOutcome()
testNoConnectedScreensOutcome()
testApplyFailureOutcome()

await MainActor.run {
    testAppStateReapplyForwardsStructuredOutcome()
}

print("verify_t64_main passed")
