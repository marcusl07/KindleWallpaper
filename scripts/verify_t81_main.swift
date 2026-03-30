import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t81_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T81-\(UUID().uuidString)"
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
private func testDeleteHighlightRefreshesLibraryState() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let deletedID = UUID(uuidString: "00000000-0000-0000-0000-000000000811")!
    let refreshedBooks = [
        Book(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000812")!,
            title: "Book",
            author: "Author",
            isEnabled: true,
            highlightCount: 0
        )
    ]

    var deletedIDs: [UUID] = []
    var fetchBooksCallCount = 0
    var fetchCountCallCount = 0

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 3,
        books: [
            Book(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000813")!,
                title: "Old Book",
                author: "Old Author",
                isEnabled: true,
                highlightCount: 3
            )
        ],
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        deleteHighlight: { deletedIDs.append($0) },
        fetchAllBooks: {
            fetchBooksCallCount += 1
            return refreshedBooks
        },
        fetchTotalHighlightCount: {
            fetchCountCallCount += 1
            return 2
        }
    )

    appState.deleteHighlight(id: deletedID)

    assertEqual(deletedIDs, [deletedID], "Expected deleteHighlight to invoke the delete action with the provided id")
    assertEqual(fetchBooksCallCount, 1, "Expected deleting a highlight to refresh books once")
    assertEqual(fetchCountCallCount, 1, "Expected deleting a highlight to refresh the total count once")
    assertEqual(appState.totalHighlightCount, 2, "Expected deleting a highlight to publish the refreshed total count")
    assertEqual(appState.books.count, refreshedBooks.count, "Expected deleting a highlight to publish refreshed books")
    assertEqual(appState.books.first?.id, refreshedBooks.first?.id, "Expected deleting a highlight to publish the refreshed book id")
    assertEqual(appState.books.first?.highlightCount, refreshedBooks.first?.highlightCount, "Expected deleting a highlight to publish the refreshed highlight count")
}

@MainActor
private func testLoadAllHighlightsRemainsInjectedBoundary() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let expectedHighlight = Highlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000814")!,
        bookId: nil,
        quoteText: "Manual quote",
        bookTitle: "",
        author: "",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil,
        isEnabled: true
    )

    var fetchHighlightsCallCount = 0
    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        fetchAllHighlights: {
            fetchHighlightsCallCount += 1
            return [expectedHighlight]
        }
    )

    let loadedHighlights = appState.loadAllHighlights()

    assertEqual(fetchHighlightsCallCount, 1, "Expected loadAllHighlights to keep using the injected fetch boundary")
    assertEqual(loadedHighlights.count, 1, "Expected loadAllHighlights to return the fetched highlights")
    assertEqual(loadedHighlights.first?.id, expectedHighlight.id, "Expected loadAllHighlights to return the fetched highlight id")
    assertEqual(loadedHighlights.first?.quoteText, expectedHighlight.quoteText, "Expected loadAllHighlights to return the fetched highlight text")
    assertTrue(appState.totalHighlightCount == 0, "Expected unrelated highlight loading not to mutate totalHighlightCount")
}

MainActor.assumeIsolated {
    testDeleteHighlightRefreshesLibraryState()
    testLoadAllHighlightsRemainsInjectedBoundary()
}

print("verify_t81_main passed")
