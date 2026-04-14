import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t110a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func testSettingsImportRefreshDecisionAppliesSnapshotWhenAvailable() {
    let expectedSnapshot = LibrarySnapshot(
        totalHighlightCount: 7,
        books: [
            Book(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001101")!,
                title: "Imported Book",
                author: "Imported Author",
                isEnabled: true,
                highlightCount: 7
            )
        ]
    )

    let refreshDecision = SettingsImportFlowTestProbe.refreshDecision(for: expectedSnapshot)

    assertEqual(refreshDecision.mode, "applySnapshot", "Expected settings import flow to apply the returned library snapshot")
    assertEqual(refreshDecision.snapshot, expectedSnapshot, "Expected settings import flow to preserve the returned library snapshot")
}

private func testSettingsImportRefreshDecisionFallsBackToRefreshWithoutSnapshot() {
    let refreshDecision = SettingsImportFlowTestProbe.refreshDecision(for: nil)

    assertEqual(refreshDecision.mode, "refreshLibraryState", "Expected settings import flow to fall back to a full refresh when no snapshot is returned")
    assertEqual(refreshDecision.snapshot, nil, "Expected refresh fallback to avoid fabricating a library snapshot")
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T110-\(UUID().uuidString)"
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
private func testBulkDeleteAppliesReturnedSnapshotWithoutRefreshQueries() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let deletedIDs = [
        UUID(uuidString: "00000000-0000-0000-0000-000000001102")!,
        UUID(uuidString: "00000000-0000-0000-0000-000000001103")!
    ]
    let refreshedBooks = [
        Book(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001104")!,
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
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001105")!,
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
}

@MainActor
private func testBulkBookDeleteAppliesReturnedSnapshotWithoutRefreshQueries() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let deletionPlan = BulkBookDeletionPlan(
        bookIDs: [UUID(uuidString: "00000000-0000-0000-0000-000000001106")!],
        linkedHighlights: [
            BulkBookDeletionLinkedHighlight(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001107")!,
                bookTitle: "Book To Delete",
                author: "Author To Delete",
                location: nil,
                quoteText: "Quote to delete"
            )
        ]
    )
    let refreshedBooks = [
        Book(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001108")!,
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
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001109")!,
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
}

@main
struct VerifyT110AMain {
    static func main() {
        testSettingsImportRefreshDecisionAppliesSnapshotWhenAvailable()
        testSettingsImportRefreshDecisionFallsBackToRefreshWithoutSnapshot()
        MainActor.assumeIsolated {
            testBulkDeleteAppliesReturnedSnapshotWithoutRefreshQueries()
            testBulkBookDeleteAppliesReturnedSnapshotWithoutRefreshQueries()
        }
        print("verify_t110a_main passed")
    }
}
