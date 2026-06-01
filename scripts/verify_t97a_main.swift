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
    let legacyDefaults: UserDefaults
    let appGroupDefaults: UserDefaults
    let appGroupGeneratedWallpapersDirectoryURL: URL
    let legacySuiteName: String
    let appGroupSuiteName: String

    static func make() throws -> Fixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent("kindlewall-t97a-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let legacySuiteName = "verify_t97a.legacy.\(UUID().uuidString)"
        let appGroupSuiteName = "verify_t97a.appgroup.\(UUID().uuidString)"
        guard
            let legacyDefaults = UserDefaults(suiteName: legacySuiteName),
            let appGroupDefaults = UserDefaults(suiteName: appGroupSuiteName)
        else {
            throw NSError(domain: "verify_t97a", code: 1)
        }

        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        appGroupDefaults.removePersistentDomain(forName: appGroupSuiteName)

        return Fixture(
            rootURL: rootURL,
            legacyDefaults: legacyDefaults,
            appGroupDefaults: appGroupDefaults,
            appGroupGeneratedWallpapersDirectoryURL: rootURL.appendingPathComponent("generated-wallpapers", isDirectory: true),
            legacySuiteName: legacySuiteName,
            appGroupSuiteName: appGroupSuiteName
        )
    }

    func cleanup() {
        legacyDefaults.removePersistentDomain(forName: legacySuiteName)
        appGroupDefaults.removePersistentDomain(forName: appGroupSuiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func makeWallpaper(path: URL, target: String) -> StoredGeneratedWallpaper {
    StoredGeneratedWallpaper(targetIdentifier: target, fileURL: path)
}

private func testSuccessfulMigrationCopiesFilesAndMarksCompletion() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let sourceDirectory = fixture.rootURL.appendingPathComponent("legacy-source", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)

    let firstSource = sourceDirectory.appendingPathComponent("first.png")
    let secondSource = sourceDirectory.appendingPathComponent("second.png")
    try Data("first".utf8).write(to: firstSource)
    try Data("second".utf8).write(to: secondSource)

    fixture.legacyDefaults.replaceReusableGeneratedWallpapers([
        makeWallpaper(path: firstSource, target: "display-a"),
        makeWallpaper(path: secondSource, target: "display-b")
    ])

    let legacyAssignmentsBefore = fixture.legacyDefaults.dictionary(forKey: WallpaperAssignmentStore.assignmentKey)

    let didMigrate = try fixture.legacyDefaults.migrateWallpaperAssignmentsToAppGroupIfNeeded(
        appGroupDefaults: fixture.appGroupDefaults,
        appGroupGeneratedWallpapersDirectoryURL: fixture.appGroupGeneratedWallpapersDirectoryURL
    )

    assertTrue(didMigrate, "Expected migration to run")
    assertTrue(fixture.appGroupDefaults.wallpaperAssignmentsAppGroupMigrationCompleted, "Expected App Group completion flag to be set")

    let migratedAssignments = fixture.appGroupDefaults.loadReusableGeneratedWallpapers(fileManager: .default)
    assertEqual(migratedAssignments.count, 2, "Expected all existing assignments to migrate")
    assertEqual(migratedAssignments.map(\.targetIdentifier), ["display-a", "display-b"], "Expected migrated assignments to remain sorted")

    for wallpaper in migratedAssignments {
        assertTrue(FileManager.default.fileExists(atPath: wallpaper.fileURL.path), "Expected migrated wallpaper file to exist")
        let contents = try Data(contentsOf: wallpaper.fileURL)
        assertTrue(contents == Data(wallpaper.targetIdentifier == "display-a" ? "first".utf8 : "second".utf8), "Expected copied file contents to match source")
    }

    let rereadAssignments = fixture.appGroupDefaults.loadReusableGeneratedWallpapers(fileManager: .default)
    assertEqual(rereadAssignments, migratedAssignments, "Expected App Group assignments to survive a read-back round trip")
    assertEqual(
        fixture.legacyDefaults.dictionary(forKey: WallpaperAssignmentStore.assignmentKey) as NSDictionary?,
        legacyAssignmentsBefore as NSDictionary?,
        "Expected legacy assignment payload to remain unchanged"
    )
}

private func testMigrationSkipsMissingSourcesAndStillSucceeds() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let sourceDirectory = fixture.rootURL.appendingPathComponent("legacy-missing", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    let existingSource = sourceDirectory.appendingPathComponent("existing.png")
    let missingSource = sourceDirectory.appendingPathComponent("missing.png")
    try Data("existing".utf8).write(to: existingSource)

    fixture.legacyDefaults.replaceReusableGeneratedWallpapers([
        makeWallpaper(path: existingSource, target: "display-a"),
        makeWallpaper(path: missingSource, target: "display-b")
    ])

    _ = try fixture.legacyDefaults.migrateWallpaperAssignmentsToAppGroupIfNeeded(
        appGroupDefaults: fixture.appGroupDefaults,
        appGroupGeneratedWallpapersDirectoryURL: fixture.appGroupGeneratedWallpapersDirectoryURL
    )

    let migratedAssignments = fixture.appGroupDefaults.loadReusableGeneratedWallpapers(fileManager: .default)
    assertEqual(migratedAssignments.count, 1, "Expected missing source files to be skipped")
    assertEqual(migratedAssignments.first?.targetIdentifier, "display-a", "Expected the existing assignment to migrate")
    assertTrue(FileManager.default.fileExists(atPath: migratedAssignments.first!.fileURL.path), "Expected the migrated file to exist")
    assertTrue(
        fixture.legacyDefaults.dictionary(forKey: WallpaperAssignmentStore.assignmentKey) != nil,
        "Expected legacy store to remain untouched"
    )
}

private func testPartialFailureLeavesBothStoresUntouched() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let sourceDirectory = fixture.rootURL.appendingPathComponent("legacy-failure", isDirectory: true)
    try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
    let firstSource = sourceDirectory.appendingPathComponent("first.png")
    try Data("first".utf8).write(to: firstSource)

    fixture.legacyDefaults.replaceReusableGeneratedWallpapers([
        makeWallpaper(path: firstSource, target: "display-a")
    ])

    let blockingContainer = fixture.rootURL.appendingPathComponent("blocked-container", isDirectory: false)
    try Data("blocker".utf8).write(to: blockingContainer, options: .atomic)

    do {
        _ = try fixture.legacyDefaults.migrateWallpaperAssignmentsToAppGroupIfNeeded(
            appGroupDefaults: fixture.appGroupDefaults,
            appGroupGeneratedWallpapersDirectoryURL: blockingContainer.appendingPathComponent("generated-wallpapers", isDirectory: true)
        )
        fail("Expected migration to fail when the App Group wallpaper directory cannot be created")
    } catch {
        // Expected
    }

    assertTrue(!fixture.appGroupDefaults.wallpaperAssignmentsAppGroupMigrationCompleted, "Expected App Group completion flag to remain unset")
    assertEqual(
        fixture.appGroupDefaults.loadReusableGeneratedWallpapers(fileManager: .default).count,
        0,
        "Expected App Group assignments to remain untouched on failure"
    )
    assertTrue(
        fixture.legacyDefaults.dictionary(forKey: WallpaperAssignmentStore.assignmentKey) != nil,
        "Expected legacy assignments to remain untouched on failure"
    )
}

do {
    try testSuccessfulMigrationCopiesFilesAndMarksCompletion()
    try testMigrationSkipsMissingSourcesAndStillSucceeds()
    try testPartialFailureLeavesBothStoresUntouched()
    print("verify_t97a_main passed")
} catch {
    fail("Unexpected error: \(error)")
}
