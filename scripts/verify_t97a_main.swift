import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t97a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fail("\(message). Expected \(expected), got \(actual)")
    }
}

private struct Fixture {
    let rootURL: URL
    let defaults: UserDefaults
    let suiteName: String

    static func make() throws -> Fixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory
            .appendingPathComponent("kindlewall-t97a-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let suiteName = "verify_t97a.shared.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "verify_t97a", code: 1)
        }
        defaults.removePersistentDomain(forName: suiteName)

        return Fixture(rootURL: rootURL, defaults: defaults, suiteName: suiteName)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func makeWallpaper(path: URL, target: String) -> StoredGeneratedWallpaper {
    StoredGeneratedWallpaper(
        targetIdentifier: target,
        fileURL: path,
        pixelWidth: 100,
        pixelHeight: 200,
        backingScaleFactor: 2,
        originX: 10,
        originY: 20
    )
}

private func testSharedStoragePathsAreUnsignedLocalAppSupport() {
    let sharedContainerURL = KindleWallSharedStorage.sharedContainerURL()
    let generatedDirectoryURL = KindleWallSharedStorage.generatedWallpapersDirectoryURL()

    assertTrue(
        sharedContainerURL.path.hasSuffix("/Library/Application Support/KindleWall"),
        "Expected shared storage under local Application Support"
    )
    assertEqual(
        generatedDirectoryURL.lastPathComponent,
        "generated-wallpapers",
        "Expected generated wallpaper directory name to stay stable"
    )
    assertEqual(
        generatedDirectoryURL.deletingLastPathComponent().standardizedFileURL,
        sharedContainerURL.standardizedFileURL,
        "Expected generated wallpapers to live below the shared container"
    )
    assertEqual(
        KindleWallSharedStorage.sharedDefaultsSuiteName,
        "com.marcuslo.KindleWall",
        "Expected helper and main app to share the main app defaults domain"
    )
    let markerKey = "verify-shared-defaults-\(UUID().uuidString)"
    KindleWallSharedStorage.sharedUserDefaults().set("ok", forKey: markerKey)
    assertEqual(
        UserDefaults(suiteName: KindleWallSharedStorage.sharedDefaultsSuiteName)?.string(forKey: markerKey),
        "ok",
        "Expected shared defaults to round trip through the unsigned local suite"
    )
    KindleWallSharedStorage.sharedUserDefaults().removeObject(forKey: markerKey)
}

private func testAssignmentRoundTripAndFiltering() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let firstSource = fixture.rootURL.appendingPathComponent("first.png")
    let secondSource = fixture.rootURL.appendingPathComponent("second.png")
    let missingSource = fixture.rootURL.appendingPathComponent("missing.png")
    try Data("first".utf8).write(to: firstSource)
    try Data("second".utf8).write(to: secondSource)

    fixture.defaults.replaceReusableGeneratedWallpapers([
        makeWallpaper(path: secondSource, target: " display-b "),
        makeWallpaper(path: firstSource, target: "display-a"),
        makeWallpaper(path: missingSource, target: "display-c"),
        makeWallpaper(path: firstSource, target: " ")
    ])

    let loaded = fixture.defaults.loadReusableGeneratedWallpapers(fileManager: .default)
    assertEqual(loaded.map(\.targetIdentifier), ["display-a", "display-b"], "Expected valid assignments to be sorted and filtered")
    assertEqual(loaded.map(\.fileURL), [firstSource.standardizedFileURL, secondSource.standardizedFileURL], "Expected persisted paths to survive round trip")
    assertEqual(loaded.first?.pixelWidth, 100, "Expected display metadata to persist")
    assertEqual(loaded.first?.pixelHeight, 200, "Expected display metadata to persist")
    assertEqual(loaded.first?.backingScaleFactor, 2, "Expected display metadata to persist")
    assertEqual(loaded.first?.originX, 10, "Expected display metadata to persist")
    assertEqual(loaded.first?.originY, 20, "Expected display metadata to persist")

    let persistedPayload = fixture.defaults.dictionary(forKey: WallpaperAssignmentStore.assignmentKey)
    assertEqual(persistedPayload?.keys.sorted(), ["display-a", "display-b"], "Expected invalid entries to be pruned from defaults")
}

private func testMergePreservesExistingAssignments() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let firstSource = fixture.rootURL.appendingPathComponent("first.png")
    let secondSource = fixture.rootURL.appendingPathComponent("second.png")
    try Data("first".utf8).write(to: firstSource)
    try Data("second".utf8).write(to: secondSource)

    fixture.defaults.replaceReusableGeneratedWallpapers([
        makeWallpaper(path: firstSource, target: "display-a")
    ])
    fixture.defaults.mergeReusableGeneratedWallpapers([
        makeWallpaper(path: secondSource, target: "display-b")
    ])

    let loaded = fixture.defaults.loadReusableGeneratedWallpapers(fileManager: .default)
    assertEqual(loaded.map(\.targetIdentifier), ["display-a", "display-b"], "Expected merge to preserve existing assignments")

    fixture.defaults.clearReusableGeneratedWallpapers()
    assertTrue(fixture.defaults.loadReusableGeneratedWallpapers(fileManager: .default).isEmpty, "Expected clear to remove all assignments")
}

do {
    testSharedStoragePathsAreUnsignedLocalAppSupport()
    try testAssignmentRoundTripAndFiltering()
    try testMergePreservesExistingAssignments()
    print("verify_t97a_main passed")
} catch {
    fail("Unexpected error: \(error)")
}
