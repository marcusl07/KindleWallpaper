import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t131a_main failed: \(message)\n", stderr)
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

private final class LockedRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var pagePayloadSearchTexts: [String] = []
    private var pageSearchTexts: [(searchText: String, offset: Int)] = []

    func recordPagePayload(searchText: String) {
        lock.lock()
        pagePayloadSearchTexts.append(searchText)
        lock.unlock()
    }

    func recordPage(searchText: String, offset: Int) {
        lock.lock()
        pageSearchTexts.append((searchText, offset))
        lock.unlock()
    }

    func snapshot() -> (pagePayloadSearchTexts: [String], pageSearchTexts: [(searchText: String, offset: Int)]) {
        lock.lock()
        let snapshot = (pagePayloadSearchTexts, pageSearchTexts)
        lock.unlock()
        return snapshot
    }
}

private func makeHighlight(id: UUID, quoteText: String) -> Highlight {
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

private func makeService(recorder: LockedRecorder) -> QuotesQueryService {
    QuotesQueryService(
        fetchPagePayload: { searchText, _, _, limit, offset in
            recorder.recordPagePayload(searchText: searchText)
            assertEqual(limit, 100, "Expected refreshes to use the standard quotes page size")
            assertEqual(offset, 0, "Expected refreshes to request the first page payload")
            return QuotesPagePayload(
                highlights: [
                    makeHighlight(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001311")!,
                        quoteText: searchText
                    )
                ],
                totalMatchingHighlightCount: 1
            )
        },
        fetchFilterOptions: { _, _ in
            QuotesFilterOptionsPayload(
                availableBookTitles: [],
                availableAuthors: []
            )
        },
        fetchHighlightsPage: { searchText, _, _, limit, offset in
            recorder.recordPage(searchText: searchText, offset: offset)
            assertEqual(limit, 100, "Expected paging to use the standard quotes page size")
            return [
                makeHighlight(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000001312")!,
                    quoteText: searchText
                )
            ]
        }
    )
}

private func requireRefreshQueryState(
    reason: String,
    effectiveSearchText: String,
    searchTextOverride: String? = nil
) -> (searchText: String, shouldCancelPendingSearchRefresh: Bool) {
    guard let state = QuotesListViewTestProbe.refreshQueryState(
        reason: reason,
        effectiveSearchText: effectiveSearchText,
        searchTextOverride: searchTextOverride
    ) else {
        fail("Expected \(reason) to map to a valid refresh query state")
    }

    return state
}

private func testNonSearchRefreshesKeepUsingCommittedSearchText() async {
    let recorder = LockedRecorder()
    let service = makeService(recorder: recorder)
    let reasons = [
        "sortChanged",
        "bookFilterChanged",
        "authorFilterChanged",
        "bookStatusChanged",
        "sourceFilterChanged",
        "libraryChanged"
    ]

    for reason in reasons {
        let refreshState = requireRefreshQueryState(
            reason: reason,
            effectiveSearchText: "committed"
        )
        assertEqual(refreshState.searchText, "committed", "Expected \(reason) refreshes to keep using the committed search text")
        assertTrue(
            !refreshState.shouldCancelPendingSearchRefresh,
            "Expected \(reason) refreshes to preserve the pending debounced search commit"
        )

        _ = await QuotesListViewTestProbe.simulateRefresh(
            reason: reason,
            capturedGeneration: 1,
            activeQueryGeneration: { 1 },
            preservingHighlights: [],
            totalMatchingHighlightCount: 0,
            availableBookTitles: [],
            availableAuthors: [],
            searchText: refreshState.searchText,
            filters: QuotesListFilters(),
            sortMode: .mostRecentlyAdded,
            quotesQueryService: service
        )
    }

    let snapshot = recorder.snapshot()
    assertEqual(
        snapshot.pagePayloadSearchTexts,
        Array(repeating: "committed", count: reasons.count),
        "Expected every non-search refresh to query using the committed search text"
    )
}

private func testDebouncedSearchRefreshUsesCommittedOverride() {
    let refreshState = requireRefreshQueryState(
        reason: "searchChanged",
        effectiveSearchText: "committed",
        searchTextOverride: "draft"
    )

    assertEqual(refreshState.searchText, "draft", "Expected debounced search commits to use the newly committed search text")
    assertTrue(
        refreshState.shouldCancelPendingSearchRefresh,
        "Expected committed search refreshes to replace any older pending debounce task"
    )
}

private func testPagingUsesCommittedSearchText() async {
    let recorder = LockedRecorder()
    let service = makeService(recorder: recorder)
    let effectiveSearchText = QuotesListViewTestProbe.pagingSearchText(
        effectiveSearchText: "committed"
    )

    _ = await service.loadPage(
        searchText: effectiveSearchText,
        filters: QuotesListFilters(),
        sortedBy: .mostRecentlyAdded,
        limit: 100,
        offset: 40
    )

    let snapshot = recorder.snapshot()
    assertEqual(
        snapshot.pageSearchTexts.map(\.searchText),
        ["committed"],
        "Expected paging requests to keep using the committed search text while typing is still debounced"
    )
    assertEqual(
        snapshot.pageSearchTexts.map(\.offset),
        [40],
        "Expected paging requests to preserve the current offset"
    )
}

@main
struct VerifyT131AMain {
    static func main() async {
        await testNonSearchRefreshesKeepUsingCommittedSearchText()
        testDebouncedSearchRefreshUsesCommittedOverride()
        await testPagingUsesCommittedSearchText()
        print("verify_t131a_main passed")
    }
}
