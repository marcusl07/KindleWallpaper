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
    fputs("verify_t134a_main failed: \(message)\n", stderr)
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
    let suiteName = "KindleWall-T134A-\(UUID().uuidString)"
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

private func makeHighlightTarget(_ id: UUID) -> BulkHighlightDeletionTarget {
    BulkHighlightDeletionTarget(
        id: id,
        bookTitle: "Book \(id.uuidString.prefix(4))",
        author: "Author",
        location: "Loc 1",
        quoteText: "Quote \(id.uuidString.prefix(4))"
    )
}

private func makeLinkedHighlight(id: UUID, bookID: UUID) -> BulkBookDeletionLinkedHighlight {
    BulkBookDeletionLinkedHighlight(
        id: id,
        bookID: bookID,
        bookTitle: "Book \(bookID.uuidString.prefix(4))",
        author: "Author",
        location: nil,
        quoteText: "Linked quote"
    )
}

@MainActor
private func testPrepareBulkHighlightDeletionReturnsCapturedPlan() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let requestedIDs = [
        UUID(uuidString: "00000000-0000-0000-0000-000000001341")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000001342")!
    ]
    let expectedPlan = BulkHighlightDeletionPlan(
        highlights: [makeHighlightTarget(requestedIDs[1])]
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
        prepareBulkHighlightDeletion: { highlightIDs in
            capturedRequests.append(highlightIDs)
            return expectedPlan
        }
    )

    let plan = appState.prepareBulkHighlightDeletion(highlightIDs: requestedIDs)

    assertEqual(capturedRequests, [requestedIDs], "Expected highlight plan preparation to request the selected IDs once")
    assertEqual(plan, expectedPlan, "Expected highlight plan preparation to return the injected captured plan")
}

@MainActor
private func testDeleteHighlightsUsingCapturedPlanSkipsLiveRefetchFallback() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let capturedPlan = BulkHighlightDeletionPlan(
        highlights: [makeHighlightTarget(UUID(uuidString: "00000000-0000-0000-0000-000000001343")!)]
    )
    var deletedPlans: [BulkHighlightDeletionPlan] = []
    var deletedIDs: [[UUID]] = []

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 2,
        books: [],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        deleteHighlights: { ids in
            deletedIDs.append(ids)
            return LibrarySnapshot(totalHighlightCount: 1, books: [])
        },
        deleteCapturedHighlights: { plan in
            deletedPlans.append(plan)
            return LibrarySnapshot(totalHighlightCount: 1, books: [])
        }
    )

    appState.deleteHighlights(using: capturedPlan)

    assertEqual(deletedPlans, [capturedPlan], "Expected captured highlight delete to invoke the captured-plan delete action")
    assertEqual(deletedIDs, [], "Expected captured highlight delete to avoid the legacy id-based path")
    assertEqual(appState.totalHighlightCount, 1, "Expected captured highlight delete to publish the returned snapshot")
}

private func testQuotePendingDeletionPlanReconcilesToVisibleRows() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000001344")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000001345")!
    let pendingPlan = BulkHighlightDeletionPlan(
        highlights: [makeHighlightTarget(firstID), makeHighlightTarget(secondID)]
    )

    let reconciledPlan = QuotesListViewTestProbe.reconciledPendingDeletionPlan(
        pendingPlan,
        validHighlightIDs: [secondID]
    )

    assertEqual(
        reconciledPlan,
        BulkHighlightDeletionPlan(highlights: [makeHighlightTarget(secondID)]),
        "Expected quote pending deletion plan reconciliation to keep only still-visible captured rows"
    )
    assertNil(
        QuotesListViewTestProbe.reconciledPendingDeletionPlan(pendingPlan, validHighlightIDs: []),
        "Expected quote pending deletion plan reconciliation to clear stale empty plans"
    )
}

private func testBookPendingDeletionPlanReconcilesToVisibleBooks() {
    let firstBookID = UUID(uuidString: "00000000-0000-0000-0000-000000001346")!
    let secondBookID = UUID(uuidString: "00000000-0000-0000-0000-000000001347")!
    let plan = BulkBookDeletionPlan(
        bookIDs: [firstBookID, secondBookID],
        linkedHighlights: [
            makeLinkedHighlight(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001348")!,
                bookID: firstBookID
            ),
            makeLinkedHighlight(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001349")!,
                bookID: secondBookID
            )
        ]
    )

    let reconciledPlan = BooksListViewTestProbe.reconciledPendingDeletionPlan(
        plan,
        validBookIDs: [secondBookID]
    )

    assertEqual(
        reconciledPlan,
        BulkBookDeletionPlan(
            bookIDs: [secondBookID],
            linkedHighlights: [
                makeLinkedHighlight(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000001349")!,
                    bookID: secondBookID
                )
            ]
        ),
        "Expected book pending deletion plan reconciliation to keep only still-visible books and linked quotes"
    )
    assertNil(
        BooksListViewTestProbe.reconciledPendingDeletionPlan(plan, validBookIDs: []),
        "Expected book pending deletion plan reconciliation to clear stale empty plans"
    )
}

private func testQuoteConfirmationMessagingUsesCapturedPlanCounts() {
    let plan = BulkHighlightDeletionPlan(
        highlights: [
            makeHighlightTarget(UUID(uuidString: "00000000-0000-0000-0000-000000001350")!),
            makeHighlightTarget(UUID(uuidString: "00000000-0000-0000-0000-000000001351")!)
        ]
    )

    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationTitle(plan: plan),
        "Delete 2 Quotes?",
        "Expected quote delete title to use the captured plan count"
    )
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationMessage(plan: plan),
        "This will permanently remove 2 selected quotes from your library.",
        "Expected quote delete message to use the captured plan count"
    )
}

testQuotePendingDeletionPlanReconcilesToVisibleRows()
testBookPendingDeletionPlanReconcilesToVisibleBooks()
testQuoteConfirmationMessagingUsesCapturedPlanCounts()

Task {
    await testPrepareBulkHighlightDeletionReturnsCapturedPlan()
    await testDeleteHighlightsUsingCapturedPlanSkipsLiveRefetchFallback()
    print("verify_t134a_main passed")
    exit(0)
}

RunLoop.main.run()
