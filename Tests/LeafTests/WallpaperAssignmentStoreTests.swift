import XCTest
@testable import KindleWall

final class WallpaperAssignmentStoreTests: XCTestCase {
    private var rootURL: URL!
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        suiteName = "LeafTests-\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: rootURL)
        defaults = nil
        suiteName = nil
        rootURL = nil
        try super.tearDownWithError()
    }

    func testSharedStoragePathsStayInUnsignedLocalAppSupport() {
        let sharedContainerURL = KindleWallSharedStorage.sharedContainerURL()
        let generatedDirectoryURL = KindleWallSharedStorage.generatedWallpapersDirectoryURL()

        XCTAssertTrue(sharedContainerURL.path.hasSuffix("/Library/Application Support/KindleWall"))
        XCTAssertEqual(generatedDirectoryURL.lastPathComponent, "generated-wallpapers")
        XCTAssertEqual(
            generatedDirectoryURL.deletingLastPathComponent().standardizedFileURL,
            sharedContainerURL.standardizedFileURL
        )
        XCTAssertEqual(KindleWallSharedStorage.sharedDefaultsSuiteName, "com.marcuslo.KindleWall")
    }

    func testAssignmentRoundTripFiltersInvalidEntriesAndPreservesMetadata() throws {
        let firstSource = try writeFixture(named: "first.png")
        let secondSource = try writeFixture(named: "second.png")
        let missingSource = rootURL.appendingPathComponent("missing.png")

        defaults.replaceReusableGeneratedWallpapers([
            makeWallpaper(path: secondSource, target: " display-b "),
            makeWallpaper(path: firstSource, target: "display-a"),
            makeWallpaper(path: missingSource, target: "display-c"),
            makeWallpaper(path: firstSource, target: " ")
        ])

        let loaded = defaults.loadReusableGeneratedWallpapers(fileManager: .default)

        XCTAssertEqual(loaded.map(\.targetIdentifier), ["display-a", "display-b"])
        XCTAssertEqual(loaded.map(\.fileURL), [firstSource.standardizedFileURL, secondSource.standardizedFileURL])
        XCTAssertEqual(loaded.first?.pixelWidth, 100)
        XCTAssertEqual(loaded.first?.pixelHeight, 200)
        XCTAssertEqual(loaded.first?.backingScaleFactor, 2)
        XCTAssertEqual(loaded.first?.originX, 10)
        XCTAssertEqual(loaded.first?.originY, 20)
        XCTAssertEqual(
            defaults.dictionary(forKey: WallpaperAssignmentStore.assignmentKey)?.keys.sorted(),
            ["display-a", "display-b"]
        )
    }

    func testMergePreservesExistingAssignmentsAndClearRemovesThem() throws {
        let firstSource = try writeFixture(named: "first.png")
        let secondSource = try writeFixture(named: "second.png")

        defaults.replaceReusableGeneratedWallpapers([
            makeWallpaper(path: firstSource, target: "display-a")
        ])
        defaults.mergeReusableGeneratedWallpapers([
            makeWallpaper(path: secondSource, target: "display-b")
        ])

        XCTAssertEqual(
            defaults.loadReusableGeneratedWallpapers(fileManager: .default).map(\.targetIdentifier),
            ["display-a", "display-b"]
        )

        defaults.clearReusableGeneratedWallpapers()
        XCTAssertTrue(defaults.loadReusableGeneratedWallpapers(fileManager: .default).isEmpty)
    }

    private func writeFixture(named filename: String) throws -> URL {
        let url = rootURL.appendingPathComponent(filename)
        try Data(filename.utf8).write(to: url)
        return url
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
}
