import Foundation

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("verify_t56_main failed: \(message)\n", stderr)
        exit(1)
    }
}

private func expectThrows(_ message: String, _ block: () throws -> Void) {
    do {
        try block()
        fputs("verify_t56_main failed: \(message)\n", stderr)
        exit(1)
    } catch {
        // Expected
    }
}

private struct Fixture {
    let rootURL: URL
    let appSupportURL: URL
    let defaults: UserDefaults
    let defaultsSuiteName: String

    static func make(appSupportURL: URL? = nil) throws -> Fixture {
        let fm = FileManager.default
        let rootURL = fm.temporaryDirectory.appendingPathComponent("kindlewall-t56-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let resolvedAppSupportURL = appSupportURL ?? rootURL.appendingPathComponent("ApplicationSupport/KindleWall", isDirectory: true)
        let suiteName = "verify_t56.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "verify_t56",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create UserDefaults suite"]
            )
        }
        defaults.removePersistentDomain(forName: suiteName)

        return Fixture(
            rootURL: rootURL,
            appSupportURL: resolvedAppSupportURL,
            defaults: defaults,
            defaultsSuiteName: suiteName
        )
    }

    func makeStore() -> BackgroundImageStore {
        BackgroundImageStore(
            fileManager: .default,
            userDefaults: defaults,
            appSupportDirectoryURL: appSupportURL
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func writeManifest(
    records: [(id: UUID, filename: String, addedAt: Date)],
    to appSupportURL: URL
) throws {
    let backgroundsDirectory = appSupportURL.appendingPathComponent("backgrounds", isDirectory: true)
    try FileManager.default.createDirectory(at: backgroundsDirectory, withIntermediateDirectories: true)

    let manifestURL = backgroundsDirectory.appendingPathComponent("backgrounds_manifest.json", isDirectory: false)
    let payload: [String: Any] = [
        "version": 1,
        "records": records.map { record in
            [
                "id": record.id.uuidString,
                "filename": record.filename,
                "addedAt": record.addedAt.timeIntervalSince1970 * 1000.0
            ]
        }
    ]
    let data = try JSONSerialization.data(withJSONObject: payload, options: [])
    try data.write(to: manifestURL, options: .atomic)
}

private func testLegacyMigrationCreatesCollectionAndIsIdempotent() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let legacySourceURL = fixture.rootURL.appendingPathComponent("legacy.jpg")
    try Data("legacy-image".utf8).write(to: legacySourceURL)
    fixture.defaults.set(legacySourceURL.path, forKey: "backgroundImagePath")

    let store = fixture.makeStore()
    let firstLoad = store.loadBackgroundImageCollection()
    expect(firstLoad.items.count == 1, "Expected one migrated item from legacy path")
    expect(firstLoad.urls.first != nil, "Expected migrated URL to be present")
    expect(FileManager.default.fileExists(atPath: firstLoad.urls[0].path), "Expected migrated file to exist")
    expect(fixture.defaults.string(forKey: "backgroundImagePath") == nil, "Expected legacy key to be cleared after migration")

    let secondLoad = store.loadBackgroundImageCollection()
    expect(secondLoad.items.count == 1, "Expected migration to be idempotent on subsequent loads")
    expect(secondLoad.items[0].id == firstLoad.items[0].id, "Expected migrated record identity to remain stable")
}

private func testCollectionCRUDAndLastItemInvariant() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let firstSource = fixture.rootURL.appendingPathComponent("first.png")
    let secondSource = fixture.rootURL.appendingPathComponent("second.heic")
    try Data("first".utf8).write(to: firstSource)
    try Data("second".utf8).write(to: secondSource)

    let store = fixture.makeStore()
    _ = try store.saveBackgroundImage(from: firstSource)
    let added = try store.addBackgroundImage(from: secondSource)

    let loaded = store.loadBackgroundImageCollection()
    expect(loaded.items.count == 2, "Expected two background items after add")
    expect(Set(loaded.items.map { $0.id }).contains(added.id), "Expected added background id to be present")

    let remaining = try store.removeBackgroundImage(id: loaded.items[0].id)
    expect(remaining.count == 1, "Expected one remaining item after remove")
    expectThrows("Expected removing last item to throw invariant error") {
        _ = try store.removeBackgroundImage(id: remaining[0].id)
    }
}

private func testCorruptedManifestReturnsFailureOutcome() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let backgroundsDirectory = fixture.appSupportURL
        .appendingPathComponent("backgrounds", isDirectory: true)
    try FileManager.default.createDirectory(at: backgroundsDirectory, withIntermediateDirectories: true)
    let manifestURL = backgroundsDirectory.appendingPathComponent("backgrounds_manifest.json", isDirectory: false)
    try Data("not-json".utf8).write(to: manifestURL, options: .atomic)

    let store = fixture.makeStore()
    let result = store.loadBackgroundImageCollection()
    if case .migrationFailed(.manifestDecodeFailed) = result.outcome {
        // Expected
    } else {
        fputs("verify_t56_main failed: expected manifestDecodeFailed outcome\n", stderr)
        exit(1)
    }
}

private func testPartialRecoveryRemovesMissingEntriesAndRewritesManifest() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let validImageURL = fixture.appSupportURL
        .appendingPathComponent("backgrounds", isDirectory: true)
        .appendingPathComponent("valid.png", isDirectory: false)
    try FileManager.default.createDirectory(at: validImageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("valid".utf8).write(to: validImageURL, options: .atomic)

    try writeManifest(
        records: [
            (UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!, "valid.png", Date(timeIntervalSince1970: 1_736_200_000)),
            (UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!, "missing.png", Date(timeIntervalSince1970: 1_736_200_100))
        ],
        to: fixture.appSupportURL
    )

    let store = fixture.makeStore()
    let firstLoad = store.loadBackgroundImageCollection()
    expect(firstLoad.items.count == 1, "Expected missing manifest entries to be filtered out")
    if case .partiallyRecovered(let removedInvalidEntries) = firstLoad.outcome {
        expect(removedInvalidEntries == 1, "Expected exactly one invalid entry to be removed")
    } else {
        fputs("verify_t56_main failed: expected partiallyRecovered outcome\n", stderr)
        exit(1)
    }

    let secondLoad = store.loadBackgroundImageCollection()
    expect(secondLoad.items.count == 1, "Expected repaired manifest to keep one valid entry")
    expect(secondLoad.outcome == .success, "Expected second load after repair to be success")
}

private func testLegacyKeyIsNotClearedWhenManifestWriteFails() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let unwritableAppSupportFile = fixture.rootURL.appendingPathComponent("not-a-directory")
    try Data("file".utf8).write(to: unwritableAppSupportFile, options: .atomic)

    let legacySourceURL = fixture.rootURL.appendingPathComponent("legacy-migration.png")
    try Data("legacy".utf8).write(to: legacySourceURL, options: .atomic)
    fixture.defaults.set(legacySourceURL.path, forKey: "backgroundImagePath")

    let store = BackgroundImageStore(
        fileManager: .default,
        userDefaults: fixture.defaults,
        appSupportDirectoryURL: unwritableAppSupportFile
    )

    let result = store.loadBackgroundImageCollection()
    if case .migrationFailed(.manifestWriteFailed) = result.outcome {
        // Expected
    } else {
        fputs("verify_t56_main failed: expected manifestWriteFailed migration outcome\n", stderr)
        exit(1)
    }

    expect(
        fixture.defaults.string(forKey: "backgroundImagePath") == legacySourceURL.path,
        "Expected legacy path key to remain when migration write fails"
    )
}

func runVerifyT56() throws {
    try testLegacyMigrationCreatesCollectionAndIsIdempotent()
    try testCollectionCRUDAndLastItemInvariant()
    try testCorruptedManifestReturnsFailureOutcome()
    try testPartialRecoveryRemovesMissingEntriesAndRewritesManifest()
    try testLegacyKeyIsNotClearedWhenManifestWriteFails()
    print("verify_t56_main passed")
}

try runVerifyT56()
