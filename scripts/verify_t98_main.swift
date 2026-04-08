import Foundation

enum WallpaperSetter {
    enum RestoreOutcome: Equatable {
        case fullRestore
        case partialRestore
        case noStoredWallpapers
        case noConnectedScreens
        case applyFailure
    }

    struct ResolvedScreen<Screen> {
        let screen: Screen
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
        let backingScaleFactor: CGFloat
        let originX: Int
        let originY: Int

        init(
            screen: Screen,
            identifier: String,
            pixelWidth: Int = 0,
            pixelHeight: Int = 0,
            backingScaleFactor: CGFloat = 1,
            originX: Int = 0,
            originY: Int = 0
        ) {
            self.screen = screen
            self.identifier = identifier
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.backingScaleFactor = backingScaleFactor
            self.originX = originX
            self.originY = originY
        }
    }

    typealias CurrentDesktopImageURL<Screen> = (Screen) -> URL?

    @discardableResult
    static func applySharedWallpaper<Screen>(
        imageURL: URL,
        resolvedScreens: [ResolvedScreen<Screen>],
        currentDesktopImageURL: CurrentDesktopImageURL<Screen>? = nil,
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows -> Int {
        0
    }
}

private func fail(_ message: String) -> Never {
    fputs("verify_t98_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T98-\(UUID().uuidString)"
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

@MainActor
private func testBulkDeleteRefreshesLibraryStateOnce() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let deletedIDs = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000981")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000982")!
    ]
    let refreshedBooks = [
        Book(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000983")!,
            title: "Refreshed Book",
            author: "Refreshed Author",
            isEnabled: true,
            highlightCount: 1
        )
    ]

    var deletedBatches: [[UUID]] = []
    var fetchBooksCallCount = 0
    var fetchCountCallCount = 0

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 3,
        books: [
            Book(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000984")!,
                title: "Old Book",
                author: "Old Author",
                isEnabled: true,
                highlightCount: 3
            )
        ],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        deleteHighlights: {
            deletedBatches.append($0)
            return LibrarySnapshot(totalHighlightCount: 1, books: refreshedBooks)
        },
        fetchAllBooks: {
            fetchBooksCallCount += 1
            return refreshedBooks
        },
        fetchTotalHighlightCount: {
            fetchCountCallCount += 1
            return 1
        }
    )

    appState.deleteHighlights(ids: deletedIDs)

    assertEqual(deletedBatches, [deletedIDs], "Expected bulk delete to invoke the injected batch delete action once")
    assertEqual(fetchBooksCallCount, 0, "Expected bulk delete snapshot wiring to avoid a follow-up books fetch")
    assertEqual(fetchCountCallCount, 0, "Expected bulk delete snapshot wiring to avoid a follow-up count fetch")
    assertEqual(appState.totalHighlightCount, 1, "Expected bulk delete to publish the refreshed total count")
    assertEqual(appState.books.first?.id, refreshedBooks.first?.id, "Expected bulk delete to publish refreshed books")
    assertEqual(appState.books.first?.highlightCount, refreshedBooks.first?.highlightCount, "Expected bulk delete to publish refreshed highlight counts")
}

@MainActor
private func testSingleDeleteRoutesThroughBulkDeleteBoundary() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let deletedID = UUID(uuidString: "00000000-0000-0000-0000-000000000985")!
    var deletedBatches: [[UUID]] = []

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        deleteHighlights: {
            deletedBatches.append($0)
            return LibrarySnapshot(totalHighlightCount: 0, books: [])
        }
    )

    appState.deleteHighlight(id: deletedID)

    assertEqual(deletedBatches, [[deletedID]], "Expected single delete to route through the bulk delete boundary")
}

@MainActor
private func testBulkDeleteFallsBackToLegacySingleDeleteInjection() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let deletedIDs = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000986")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000987")!
    ]
    var deletedSingles: [UUID] = []

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        deleteHighlight: { deletedSingles.append($0) }
    )

    appState.deleteHighlights(ids: deletedIDs)

    assertEqual(deletedSingles, deletedIDs, "Expected bulk delete to fall back to the legacy single-delete injection when no batch delete action is provided")
}

MainActor.assumeIsolated {
    testBulkDeleteRefreshesLibraryStateOnce()
    testSingleDeleteRoutesThroughBulkDeleteBoundary()
    testBulkDeleteFallsBackToLegacySingleDeleteInjection()
}

print("verify_t98_main passed")
