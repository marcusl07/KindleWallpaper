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

        init(screen: Screen, identifier: String, pixelWidth: Int = 0, pixelHeight: Int = 0, backingScaleFactor: CGFloat = 1, originX: Int = 0, originY: Int = 0) {
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
    static func applySharedWallpaper<Screen>(imageURL: URL, resolvedScreens: [ResolvedScreen<Screen>], currentDesktopImageURL: CurrentDesktopImageURL<Screen>? = nil, setDesktopImage: (URL, Screen) throws -> Void) rethrows -> Int {
        0
    }
}

private func fail(_ message: String) -> Never {
    fputs("verify_t135a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func assertNil<T>(_ value: T?, _ message: String) {
    if value != nil {
        fail(message)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T135A-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fail("Unable to create isolated UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "__verifySuiteName")
    return defaults
}

private func clearDefaults(_ defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: "__verifySuiteName"), !suiteName.isEmpty else { return }
    defaults.removePersistentDomain(forName: suiteName)
}

private func makeHighlightTarget(_ id: UUID) -> BulkHighlightDeletionTarget {
    BulkHighlightDeletionTarget(id: id, bookTitle: "Book", author: "Author", location: "Loc", quoteText: "Quote")
}

private func makeBookDeletionPlan(bookCount: Int, linkedHighlightCount: Int) -> BulkBookDeletionPlan {
    let bookIDs = (0..<bookCount).map { offset in
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 5000 + offset))!
    }
    let linkedHighlights = (0..<linkedHighlightCount).map { offset in
        BulkBookDeletionLinkedHighlight(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 6000 + offset))!,
            bookID: bookIDs[offset % max(bookIDs.count, 1)],
            bookTitle: "Book \(offset)",
            author: "Author \(offset)",
            location: nil,
            quoteText: "Quote \(offset)"
        )
    }
    return BulkBookDeletionPlan(bookIDs: bookIDs, linkedHighlights: linkedHighlights)
}

@MainActor
private func testQuoteDeletePlanningAndStalenessHandling() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let requestIDs = [
        UUID(uuidString: "00000000-0000-0000-0000-000000001351")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000001352")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000001353")!
    ]
    let capturedPlan = BulkHighlightDeletionPlan(highlights: [makeHighlightTarget(requestIDs[1]), makeHighlightTarget(requestIDs[2])])
    var capturedRequests: [[UUID]] = []
    var deletedPlans: [BulkHighlightDeletionPlan] = []

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 3,
        books: [],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        prepareBulkHighlightDeletion: { ids in
            capturedRequests.append(ids)
            return capturedPlan
        },
        deleteCapturedHighlights: { plan in
            deletedPlans.append(plan)
            return LibrarySnapshot(totalHighlightCount: 1, books: [])
        }
    )

    let plan = appState.prepareBulkHighlightDeletion(highlightIDs: requestIDs)
    assertEqual(capturedRequests, [requestIDs], "Expected quote delete planning to capture the original selection once")
    assertEqual(plan, capturedPlan, "Expected quote delete planning to return the captured plan")
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationTitle(plan: plan),
        "Delete 2 Quotes?",
        "Expected quote confirmation title to use the captured plan count"
    )
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationMessage(plan: plan),
        "This will permanently remove 2 selected quotes from your library.",
        "Expected quote confirmation message to use the captured plan count"
    )
    assertNil(
        QuotesListViewTestProbe.reconciledPendingDeletionPlan(capturedPlan, validHighlightIDs: []),
        "Expected stale quote deletion plans to collapse to nil"
    )

    appState.deleteHighlights(using: plan)
    assertEqual(deletedPlans, [capturedPlan], "Expected captured quote delete to execute the captured plan")
}

@MainActor
private func testBookDeletePlanningAndStalenessHandling() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let requestedIDs = [
        UUID(uuidString: "00000000-0000-0000-0000-000000001354")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000001355")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000001356")!
    ]
    let capturedPlan = makeBookDeletionPlan(bookCount: 2, linkedHighlightCount: 3)
    var capturedRequests: [[UUID]] = []
    var deletedPlans: [BulkBookDeletionPlan] = []

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 6,
        books: [],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        prepareBulkBookDeletion: { ids in
            capturedRequests.append(ids)
            return capturedPlan
        },
        deleteBooks: { plan in
            deletedPlans.append(plan)
            return LibrarySnapshot(totalHighlightCount: 3, books: [])
        }
    )

    let plan = appState.prepareBulkBookDeletion(bookIDs: requestedIDs)
    assertEqual(capturedRequests, [requestedIDs], "Expected book delete planning to capture the original selection once")
    assertEqual(plan, capturedPlan, "Expected book delete planning to return the captured plan")
    assertEqual(
        BooksListViewTestProbe.bulkDeleteConfirmationTitle(plan: plan),
        "Delete 2 Books?",
        "Expected book confirmation title to use the captured plan count"
    )
    assertEqual(
        BooksListViewTestProbe.bulkDeleteConfirmationMessage(plan: plan),
        "This will permanently remove 2 selected books and delete 3 linked quotes from your library.",
        "Expected book confirmation message to use the captured plan counts"
    )
    assertNil(
        BooksListViewTestProbe.reconciledPendingDeletionPlan(capturedPlan, validBookIDs: []),
        "Expected stale book deletion plans to collapse to nil"
    )

    appState.deleteBooks(using: plan)
    assertEqual(deletedPlans, [capturedPlan], "Expected captured book delete to execute the captured plan")
}

private func testLargeSelectionBatchCoverage() {
    let largeHighlightCount = 401
    let largeBookCount = 405
    let highlightPlan = BulkHighlightDeletionPlan(
        highlights: (0..<largeHighlightCount).map { index in
            makeHighlightTarget(UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 7000 + index))!)
        }
    )
    let bookPlan = BulkBookDeletionPlan(
        bookIDs: (0..<largeBookCount).map { index in
            UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 8000 + index))!
        },
        linkedHighlights: (0..<largeBookCount).map { index in
            BulkBookDeletionLinkedHighlight(
                id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 9000 + index))!,
                bookID: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 8000 + index))!,
                bookTitle: "Book \(index)",
                author: "Author \(index)",
                location: nil,
                quoteText: "Quote \(index)"
            )
        }
    )

    assertEqual(highlightPlan.highlightCount, largeHighlightCount, "Expected highlight plan to preserve the full large selection")
    assertEqual(bookPlan.bookCount, largeBookCount, "Expected book plan to preserve the full large selection")
    assertEqual(bookPlan.linkedHighlightCount, largeBookCount, "Expected linked highlight capture to preserve the full large selection")
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationTitle(plan: highlightPlan),
        "Delete 401 Quotes?",
        "Expected large quote confirmation title to remain count-driven"
    )
    assertEqual(
        BooksListViewTestProbe.bulkDeleteConfirmationMessage(plan: bookPlan),
        "This will permanently remove 405 selected books and delete 405 linked quotes from your library.",
        "Expected large book confirmation message to remain count-driven"
    )
}

testLargeSelectionBatchCoverage()

Task {
    await testQuoteDeletePlanningAndStalenessHandling()
    await testBookDeletePlanningAndStalenessHandling()
    print("verify_t135a_main passed")
    exit(0)
}

RunLoop.main.run()
