import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t61_main failed: \(message)\n", stderr)
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

private func testReapplyStoredWallpaperForAllScreens() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t61-all")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = directory.appendingPathComponent("all.png", isDirectory: false)
    FileManager.default.createFile(atPath: wallpaperURL.path, contents: Data("all".utf8))

    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a"),
        makeResolvedScreen(screen: "screen-b", identifier: "display-b")
    ]

    var applied: [(String, URL)] = []
    let didReapply = WallpaperSetter.reapplyStoredWallpapers(
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

    expectEqual(didReapply, true, "Expected single stored wallpaper to reapply across all screens")
    expectEqual(applied.count, 2, "Expected wallpaper to be applied to every connected screen")
    expectEqual(applied[0].0, "screen-a", "Expected first screen to receive stored wallpaper")
    expectEqual(applied[0].1.standardizedFileURL, wallpaperURL.standardizedFileURL, "Expected stored wallpaper URL to be reused")
    expectEqual(applied[1].0, "screen-b", "Expected second screen to receive stored wallpaper")
    expectEqual(applied[1].1.standardizedFileURL, wallpaperURL.standardizedFileURL, "Expected stored wallpaper URL to be reused on every screen")
}

private func testReapplyStoredWallpaperForTargetedScreens() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t61-targeted")
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = directory.appendingPathComponent("display-a.png", isDirectory: false)
    let secondURL = directory.appendingPathComponent("display-c.png", isDirectory: false)
    FileManager.default.createFile(atPath: firstURL.path, contents: Data("a".utf8))
    FileManager.default.createFile(atPath: secondURL.path, contents: Data("c".utf8))

    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a"),
        makeResolvedScreen(screen: "screen-b", identifier: "display-b"),
        makeResolvedScreen(screen: "screen-c", identifier: "display-c")
    ]

    var applied: [(String, URL)] = []
    let didReapply = WallpaperSetter.reapplyStoredWallpapers(
        [
            StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: firstURL),
            StoredGeneratedWallpaper(targetIdentifier: "display-c", fileURL: secondURL)
        ],
        resolvedScreens: screens,
        setDesktopImage: { url, screen in
            applied.append((screen, url))
        }
    )

    expectEqual(didReapply, true, "Expected targeted stored wallpapers to reapply successfully")
    expectEqual(applied.count, 2, "Expected only matching screens to receive targeted wallpapers")
    expectEqual(applied[0].0, "screen-a", "Expected first targeted screen assignment to be preserved")
    expectEqual(applied[0].1.standardizedFileURL, firstURL.standardizedFileURL, "Expected first targeted wallpaper URL to be reused")
    expectEqual(applied[1].0, "screen-c", "Expected second targeted screen assignment to be preserved")
    expectEqual(applied[1].1.standardizedFileURL, secondURL.standardizedFileURL, "Expected second targeted wallpaper URL to be reused")
}

private func testReapplyStoredWallpaperReturnsFalseWhenUnavailable() {
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a")
    ]

    let noWallpaperResult = WallpaperSetter.reapplyStoredWallpapers(
        [],
        resolvedScreens: screens,
        setDesktopImage: { _, _ in
            fail("Expected no wallpaper reapply work when storage is empty")
        }
    )
    expectEqual(noWallpaperResult, false, "Expected empty stored wallpaper list to no-op")

    let directory = makeTemporaryDirectory(prefix: "kindlewall-t61-noscreens")
    defer { try? FileManager.default.removeItem(at: directory) }
    let wallpaperURL = directory.appendingPathComponent("all.png", isDirectory: false)
    FileManager.default.createFile(atPath: wallpaperURL.path, contents: Data("all".utf8))

    let noScreenResult = WallpaperSetter.reapplyStoredWallpapers(
        [
            StoredGeneratedWallpaper(
                targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                fileURL: wallpaperURL
            )
        ],
        resolvedScreens: [WallpaperSetter.ResolvedScreen<String>](),
        setDesktopImage: { (_: URL, _: String) in
            fail("Expected no wallpaper reapply work when no screens are connected")
        }
    )
    expectEqual(noScreenResult, false, "Expected missing connected screens to no-op")
}

@MainActor
private func testAppStateReapplyUsesDedicatedClosure() {
    var reapplyCallCount = 0
    var markHighlightShownCount = 0

    let appState = AppState(
        pickNextHighlight: {
            fail("Expected wake reapply not to request a new highlight")
        },
        generateWallpaper: { _, _ in
            fail("Expected wake reapply not to generate a new wallpaper")
        },
        setWallpaper: { _ in
            fail("Expected wake reapply not to use the rotation apply path")
        },
        reapplyStoredWallpaper: {
            reapplyCallCount += 1
            return true
        },
        markHighlightShown: { _ in
            markHighlightShownCount += 1
        }
    )

    let result = appState.reapplyStoredWallpaperIfAvailable()
    expectEqual(result, true, "Expected AppState wake reapply to return the restore result")
    expectEqual(reapplyCallCount, 1, "Expected AppState wake reapply to delegate exactly once")
    expectEqual(markHighlightShownCount, 0, "Expected wake reapply not to advance the rotation state")
}

testReapplyStoredWallpaperForAllScreens()
testReapplyStoredWallpaperForTargetedScreens()
testReapplyStoredWallpaperReturnsFalseWhenUnavailable()

await MainActor.run {
    testAppStateReapplyUsesDedicatedClosure()
}

print("verify_t61_main passed")
