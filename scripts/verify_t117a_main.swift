import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t117a_main failed: \(message)\n", stderr)
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

private func testRefreshResetStateClearsPagedQuotesState() {
    let resetState = QuotesListViewTestProbe.refreshResetState(after: 4)

    assertEqual(resetState.nextQueryGeneration, 5, "Expected refreshing quotes to advance the query generation")
    assertEqual(resetState.isLoadingHighlights, true, "Expected refreshing quotes to enter the loading state")
    assertEqual(resetState.isLoadingNextPage, false, "Expected refreshing quotes to clear the next-page loading flag")
    assertEqual(resetState.hasMoreHighlights, false, "Expected refreshing quotes to clear the has-more flag")
    assertEqual(resetState.highlightCount, 0, "Expected refreshing quotes to clear the loaded highlight page")
    assertEqual(resetState.totalMatchingHighlightCount, 0, "Expected refreshing quotes to clear the matching-count snapshot")
    assertEqual(resetState.availableBookTitles, [], "Expected refreshing quotes to clear stale book filter options")
    assertEqual(resetState.availableAuthors, [], "Expected refreshing quotes to clear stale author filter options")
}

private func testInitialPageHasMoreFlagTracksRemainingResults() {
    assertTrue(
        QuotesListViewTestProbe.hasMoreHighlights(
            loadedCount: 100,
            totalMatchingHighlightCount: 120
        ),
        "Expected quotes paging to keep load-more enabled when more rows remain"
    )
    assertEqual(
        QuotesListViewTestProbe.hasMoreHighlights(
            loadedCount: 120,
            totalMatchingHighlightCount: 120
        ),
        false,
        "Expected quotes paging to disable load-more when the first page fills the full result set"
    )
}

private func testLoadMoreRequiresThresholdAndIdleState() {
    let highlightIDs = (0..<30).map { offset in
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", offset + 1))!
    }
    let highlights = highlightIDs.enumerated().map { offset, id in
        makeHighlight(id: id, quoteText: "Quote \(offset)")
    }

    assertEqual(
        QuotesListViewTestProbe.shouldLoadMore(
            highlights: highlights,
            currentHighlightID: highlightIDs[9],
            hasMoreHighlights: true,
            isLoadingHighlights: false,
            isLoadingNextPage: false,
            hasLoadMoreTask: false
        ),
        false,
        "Expected quotes load-more to stay idle before the threshold row appears"
    )
    assertTrue(
        QuotesListViewTestProbe.shouldLoadMore(
            highlights: highlights,
            currentHighlightID: highlightIDs[10],
            hasMoreHighlights: true,
            isLoadingHighlights: false,
            isLoadingNextPage: false,
            hasLoadMoreTask: false
        ),
        "Expected quotes load-more to start once the threshold row appears"
    )
    assertEqual(
        QuotesListViewTestProbe.shouldLoadMore(
            highlights: highlights,
            currentHighlightID: highlightIDs[10],
            hasMoreHighlights: true,
            isLoadingHighlights: false,
            isLoadingNextPage: false,
            hasLoadMoreTask: true
        ),
        false,
        "Expected quotes load-more to stay disabled while a page request is already in flight"
    )
}

private func testAppendingNextPageDedupesRowsAndPreservesPaging() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000001171")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000001172")!
    let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000001173")!
    let fourthID = UUID(uuidString: "00000000-0000-0000-0000-000000001174")!

    let appendResult = QuotesListViewTestProbe.appendPage(
        existingHighlights: [
            makeHighlight(id: firstID, quoteText: "First"),
            makeHighlight(id: secondID, quoteText: "Second")
        ],
        nextPage: [
            makeHighlight(id: secondID, quoteText: "Second"),
            makeHighlight(id: thirdID, quoteText: "Third"),
            makeHighlight(id: fourthID, quoteText: "Fourth")
        ],
        totalMatchingHighlightCount: 6
    )

    assertEqual(
        appendResult.highlightIDs,
        [firstID, secondID, thirdID, fourthID],
        "Expected quotes paging to append only new rows while preserving existing order"
    )
    assertEqual(
        appendResult.hasMoreHighlights,
        true,
        "Expected quotes paging to keep load-more enabled when unique rows were appended and more results remain"
    )
}

private func testAppendingDuplicateOnlyPageStopsLoadMore() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000001175")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000001176")!

    let appendResult = QuotesListViewTestProbe.appendPage(
        existingHighlights: [
            makeHighlight(id: firstID, quoteText: "First"),
            makeHighlight(id: secondID, quoteText: "Second")
        ],
        nextPage: [
            makeHighlight(id: secondID, quoteText: "Second")
        ],
        totalMatchingHighlightCount: 10
    )

    assertEqual(
        appendResult.highlightIDs,
        [firstID, secondID],
        "Expected quotes paging to ignore already-loaded rows in the next page"
    )
    assertEqual(
        appendResult.hasMoreHighlights,
        false,
        "Expected quotes paging to stop requesting more pages when the backend returns no new rows"
    )
}

testRefreshResetStateClearsPagedQuotesState()
testInitialPageHasMoreFlagTracksRemainingResults()
testLoadMoreRequiresThresholdAndIdleState()
testAppendingNextPageDedupesRowsAndPreservesPaging()
testAppendingDuplicateOnlyPageStopsLoadMore()

print("verify_t117a_main passed")
