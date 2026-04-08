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
    fputs("verify_t99_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T99-\(UUID().uuidString)"
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
private func testPrepareBulkBookDeletionReturnsCapturedPlan() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let selectedBookIDs = [
        UUID(uuidString: "00000000-0000-0000-0000-000000000991")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000000992")!
    ]
    let expectedPlan = BulkBookDeletionPlan(
        bookIDs: [selectedBookIDs[1]],
        linkedHighlights: [
            BulkBookDeletionLinkedHighlight(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000993")!,
                bookTitle: "Captured Book",
                author: "Captured Author",
                location: "Loc 42",
                quoteText: "Captured quote"
            )
        ]
    )
    var capturedRequests: [[UUID]] = []

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 0,
        books: [],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        prepareBulkBookDeletion: { requestedBookIDs in
            capturedRequests.append(requestedBookIDs)
            return expectedPlan
        }
    )

    let plan = appState.prepareBulkBookDeletion(bookIDs: selectedBookIDs)

    assertEqual(capturedRequests, [selectedBookIDs], "Expected plan preparation to request the selected books once")
    assertEqual(plan, expectedPlan, "Expected plan preparation to return the injected captured plan")
}

@MainActor
private func testDeleteBooksRefreshesLibraryStateOnce() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let deletionPlan = BulkBookDeletionPlan(
        bookIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000000994")!],
        linkedHighlights: [
            BulkBookDeletionLinkedHighlight(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000995")!,
                bookTitle: "Book To Delete",
                author: "Author To Delete",
                location: nil,
                quoteText: "Quote to delete"
            )
        ]
    )
    let refreshedBooks = [
        Book(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000996")!,
            title: "Remaining Book",
            author: "Remaining Author",
            isEnabled: true,
            highlightCount: 1
        )
    ]

    var deletedPlans: [BulkBookDeletionPlan] = []
    var fetchBooksCallCount = 0
    var fetchCountCallCount = 0

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 2,
        books: [
            Book(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000997")!,
                title: "Deleted Book",
                author: "Deleted Author",
                isEnabled: true,
                highlightCount: 2
            )
        ],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        deleteBooks: {
            deletedPlans.append($0)
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

    appState.deleteBooks(using: deletionPlan)

    assertEqual(deletedPlans, [deletionPlan], "Expected bulk book delete to invoke the injected delete action once")
    assertEqual(fetchBooksCallCount, 0, "Expected bulk book delete snapshot wiring to avoid a follow-up books fetch")
    assertEqual(fetchCountCallCount, 0, "Expected bulk book delete snapshot wiring to avoid a follow-up count fetch")
    assertEqual(appState.totalHighlightCount, 1, "Expected bulk book delete to publish the refreshed total count")
    assertEqual(appState.books.first?.id, refreshedBooks.first?.id, "Expected bulk book delete to publish refreshed books")
}

@MainActor
private func testDeleteBooksSkipsEmptyPlan() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    var deletedPlans: [BulkBookDeletionPlan] = []
    var fetchBooksCallCount = 0
    var fetchCountCallCount = 0
    let emptyPlan = BulkBookDeletionPlan(bookIDs: [], linkedHighlights: [])

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 0,
        books: [],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        deleteBooks: {
            deletedPlans.append($0)
            return LibrarySnapshot(totalHighlightCount: 0, books: [])
        },
        fetchAllBooks: {
            fetchBooksCallCount += 1
            return []
        },
        fetchTotalHighlightCount: {
            fetchCountCallCount += 1
            return 0
        }
    )

    appState.deleteBooks(using: emptyPlan)

    assertEqual(deletedPlans.count, 0, "Expected empty bulk book deletion plan to skip the delete action")
    assertEqual(fetchBooksCallCount, 0, "Expected empty bulk book deletion plan to skip book refresh")
    assertEqual(fetchCountCallCount, 0, "Expected empty bulk book deletion plan to skip count refresh")
}

MainActor.assumeIsolated {
    testPrepareBulkBookDeletionReturnsCapturedPlan()
    testDeleteBooksRefreshesLibraryStateOnce()
    testDeleteBooksSkipsEmptyPlan()
}

print("verify_t99_main passed")
