import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t122a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
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

private func testRefreshStartPreservesResolvedQuotesSnapshot() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000001221")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000001222")!
    let resetState = QuotesListViewTestProbe.refreshResetState(
        after: 7,
        preservingHighlights: [
            makeHighlight(id: firstID, quoteText: "First"),
            makeHighlight(id: secondID, quoteText: "Second")
        ],
        totalMatchingHighlightCount: 9,
        availableBookTitles: ["Book First", "Book Second"],
        availableAuthors: ["Author First", "Author Second"],
        selectedHighlightIDs: [firstID]
    )

    assertEqual(resetState.nextQueryGeneration, 8, "Expected refreshing quotes to advance the query generation")
    assertEqual(resetState.isLoadingHighlights, true, "Expected refreshing quotes to enter the loading state")
    assertEqual(resetState.isLoadingNextPage, false, "Expected refreshing quotes to clear next-page loading")
    assertEqual(resetState.hasMoreHighlights, false, "Expected refreshing quotes to reset paging while the new snapshot loads")
    assertEqual(
        resetState.highlightIDs,
        [firstID, secondID],
        "Expected refreshing quotes to preserve the previously accepted highlights until replacement data arrives"
    )
    assertEqual(
        resetState.totalMatchingHighlightCount,
        9,
        "Expected refreshing quotes to preserve the previously accepted result count until replacement data arrives"
    )
    assertEqual(
        resetState.availableBookTitles,
        ["Book First", "Book Second"],
        "Expected refreshing quotes to preserve existing book filter options until replacement data arrives"
    )
    assertEqual(
        resetState.availableAuthors,
        ["Author First", "Author Second"],
        "Expected refreshing quotes to preserve existing author filter options until replacement data arrives"
    )
    assertEqual(
        resetState.selectedHighlightIDs,
        [firstID],
        "Expected refreshing quotes to preserve selection until the replacement snapshot is accepted"
    )
}

private func testSelectionReconciliationDropsOnlyRowsMissingFromAcceptedSnapshot() {
    let preservedID = UUID(uuidString: "00000000-0000-0000-0000-000000001223")!
    let removedID = UUID(uuidString: "00000000-0000-0000-0000-000000001224")!
    let newID = UUID(uuidString: "00000000-0000-0000-0000-000000001225")!

    let reconciled = QuotesListViewTestProbe.reconciledSelection(
        [preservedID, removedID],
        validHighlightIDs: [preservedID, newID]
    )

    assertEqual(
        reconciled,
        [preservedID],
        "Expected quote selection reconciliation to run against the accepted snapshot instead of clearing eagerly at refresh start"
    )
}

testRefreshStartPreservesResolvedQuotesSnapshot()
testSelectionReconciliationDropsOnlyRowsMissingFromAcceptedSnapshot()

print("verify_t122a_main passed")
