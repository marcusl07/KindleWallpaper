import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t118a_main failed: \(message)\n", stderr)
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

private func sleepBriefly() {
    Thread.sleep(forTimeInterval: 0.2)
}

private func makeHighlight(
    id: UUID,
    quoteText: String
) -> Highlight {
    Highlight(
        id: id,
        bookId: nil,
        quoteText: quoteText,
        bookTitle: "Book \(quoteText)",
        author: "Author \(quoteText)",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil,
        isEnabled: true
    )
}

private func testLoadSnapshotFetchesAllInputsInParallel() async {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000001181")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000001182")!
    let expectedHighlights = [
        makeHighlight(id: firstID, quoteText: "First"),
        makeHighlight(id: secondID, quoteText: "Second")
    ]

    let service = QuotesQueryService(
        fetchHighlightsPage: { searchText, filters, sortMode, limit, offset in
            sleepBriefly()
            assertEqual(searchText, "needle", "Expected snapshot page fetch to receive the search text")
            assertEqual(limit, 2, "Expected snapshot page fetch to receive the requested page size")
            assertEqual(offset, 0, "Expected snapshot page fetch to start from offset zero")
            return expectedHighlights
        },
        countHighlights: { searchText, filters in
            sleepBriefly()
            assertEqual(searchText, "needle", "Expected snapshot count fetch to receive the search text")
            return 7
        },
        fetchAvailableHighlightBookTitles: { searchText, filters in
            sleepBriefly()
            assertEqual(searchText, "needle", "Expected snapshot title fetch to receive the search text")
            return ["Book First", "Book Second"]
        },
        fetchAvailableHighlightAuthors: { searchText, filters in
            sleepBriefly()
            assertEqual(searchText, "needle", "Expected snapshot author fetch to receive the search text")
            return ["Author First", "Author Second"]
        }
    )

    let start = Date()
    let snapshot = await service.loadSnapshot(
        searchText: "needle",
        filters: QuotesListFilters(),
        sortedBy: .alphabeticalByBook,
        pageSize: 2
    )
    let elapsed = Date().timeIntervalSince(start)

    assertEqual(snapshot.highlights, expectedHighlights, "Expected snapshot to return the fetched page")
    assertEqual(snapshot.totalMatchingHighlightCount, 7, "Expected snapshot to return the fetched count")
    assertEqual(snapshot.availableBookTitles, ["Book First", "Book Second"], "Expected snapshot to return book title filters")
    assertEqual(snapshot.availableAuthors, ["Author First", "Author Second"], "Expected snapshot to return author filters")
    assertTrue(
        elapsed < 0.45,
        "Expected async-let snapshot fetches to complete in parallel, elapsed \(elapsed)"
    )
}

private func testLoadPagePassesPagingInputsThrough() async {
    let expectedHighlights = [
        makeHighlight(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001183")!,
            quoteText: "Paged"
        )
    ]

    let service = QuotesQueryService(
        fetchHighlightsPage: { searchText, filters, sortMode, limit, offset in
            assertEqual(searchText, "page", "Expected page fetch to receive the search text")
            assertEqual(sortMode, .mostRecentlyAdded, "Expected page fetch to receive the sort mode")
            assertEqual(limit, 25, "Expected page fetch to receive the limit")
            assertEqual(offset, 50, "Expected page fetch to receive the offset")
            return expectedHighlights
        },
        countHighlights: { _, _ in 0 },
        fetchAvailableHighlightBookTitles: { _, _ in [] },
        fetchAvailableHighlightAuthors: { _, _ in [] }
    )

    let page = await service.loadPage(
        searchText: "page",
        filters: QuotesListFilters(),
        sortedBy: .mostRecentlyAdded,
        limit: 25,
        offset: 50
    )

    assertEqual(page, expectedHighlights, "Expected page API to return the fetch result unchanged")
}

@MainActor
private func testAppStateRetainsInjectedQuotesQueryService() {
    let service = QuotesQueryService(
        fetchHighlightsPage: { _, _, _, _, _ in [] },
        countHighlights: { _, _ in 0 },
        fetchAvailableHighlightBookTitles: { _, _ in [] },
        fetchAvailableHighlightAuthors: { _, _ in [] }
    )

    let appState = AppState(
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/wallpaper.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        quotesQueryService: service
    )

    assertTrue(appState.quotesQueryService === service, "Expected AppState to retain the injected quotes query service")
}

@main
struct VerifyT118AMain {
    static func main() async {
        await testLoadSnapshotFetchesAllInputsInParallel()
        await testLoadPagePassesPagingInputsThrough()
        testAppStateRetainsInjectedQuotesQueryService()
        print("verify_t118a_main passed")
    }
}
