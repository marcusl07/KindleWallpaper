import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t84_main failed: \(message)\n", stderr)
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

private func makeTemporaryDirectory(prefix: String) -> URL {
    let directoryURL = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)

    do {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    } catch {
        fail("Unable to create temporary directory: \(error)")
    }

    return directoryURL
}

private func makeWallpaper(directory: URL, name: String) -> URL {
    let fileURL = directory.appendingPathComponent(name, isDirectory: false)
    FileManager.default.createFile(atPath: fileURL.path, contents: Data(name.utf8))
    return fileURL
}

private func testSharedWallpaperAppliesToAllResolvedScreens() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t84-all")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "shared.png")
    let resolvedScreens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a"),
        makeResolvedScreen(screen: "screen-b", identifier: "display-b"),
        makeResolvedScreen(screen: "screen-c", identifier: "display-c")
    ]

    var applied: [(String, URL)] = []
    let appliedCount = WallpaperSetter.applySharedWallpaper(
        imageURL: wallpaperURL,
        resolvedScreens: resolvedScreens,
        setDesktopImage: { url, screen in
            applied.append((screen, url))
        }
    )

    expectEqual(appliedCount, 3, "Expected shared helper to apply the wallpaper to every resolved screen")
    expectEqual(applied.count, 3, "Expected each resolved screen to receive one wallpaper apply")
    expectEqual(applied[0].1.standardizedFileURL, wallpaperURL.standardizedFileURL, "Expected first screen to receive the canonical shared wallpaper URL")
    expectEqual(applied[2].1.standardizedFileURL, wallpaperURL.standardizedFileURL, "Expected last screen to receive the canonical shared wallpaper URL")
}

private func testSharedWallpaperSkipsScreensThatAlreadyMatchCanonicalFile() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t84-skip")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "shared.png")
    let aliasURL = directory
        .appendingPathComponent("subdir", isDirectory: true)
        .appendingPathComponent("..", isDirectory: true)
        .appendingPathComponent("shared.png", isDirectory: false)
    let differentWallpaperURL = makeWallpaper(directory: directory, name: "different.png")
    let resolvedScreens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a"),
        makeResolvedScreen(screen: "screen-b", identifier: "display-b"),
        makeResolvedScreen(screen: "screen-c", identifier: "display-c")
    ]

    var applied: [(String, URL)] = []
    let appliedCount = WallpaperSetter.applySharedWallpaper(
        imageURL: wallpaperURL,
        resolvedScreens: resolvedScreens,
        currentDesktopImageURL: { screen in
            switch screen {
            case "screen-a":
                return aliasURL
            case "screen-b":
                return differentWallpaperURL
            default:
                return nil
            }
        },
        setDesktopImage: { url, screen in
            applied.append((screen, url))
        }
    )

    expectEqual(appliedCount, 2, "Expected shared helper to skip only screens already showing the canonical file")
    expectEqual(applied.count, 2, "Expected only non-matching screens to be updated")
    expect(applied.contains { $0.0 == "screen-b" }, "Expected mismatched screen to be updated")
    expect(applied.contains { $0.0 == "screen-c" }, "Expected screen without an active wallpaper to be updated")
    expect(applied.contains { $0.0 == "screen-a" } == false, "Expected already-matching screen to be skipped")
}

private func testSharedWallpaperNoOpsWhenNoScreensAreConnected() {
    var applyCallCount = 0
    let appliedCount = WallpaperSetter.applySharedWallpaper(
        imageURL: URL(fileURLWithPath: "/tmp/shared.png"),
        resolvedScreens: [WallpaperSetter.ResolvedScreen<String>](),
        setDesktopImage: { (_: URL, _: String) in
            applyCallCount += 1
        }
    )

    expectEqual(appliedCount, 0, "Expected shared helper to report zero applies when no screens are connected")
    expectEqual(applyCallCount, 0, "Expected shared helper not to invoke the setter when no screens are connected")
}

testSharedWallpaperAppliesToAllResolvedScreens()
testSharedWallpaperSkipsScreensThatAlreadyMatchCanonicalFile()
testSharedWallpaperNoOpsWhenNoScreensAreConnected()

print("verify_t84_main passed")
