import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t127a_main failed: \(message)\n", stderr)
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

private func testRefreshResetStateAdvancesGenerationWhilePreservingResolvedSnapshot() {
    let preservedID = UUID(uuidString: "00000000-0000-0000-0000-000000001271")!
    let resetState = QuotesListViewTestProbe.refreshResetState(
        after: 11,
        preservingHighlights: [
            makeHighlight(id: preservedID, quoteText: "Preserved")
        ],
        totalMatchingHighlightCount: 4,
        availableBookTitles: ["Book Preserved"],
        availableAuthors: ["Author Preserved"],
        selectedHighlightIDs: [preservedID]
    )

    assertEqual(resetState.nextQueryGeneration, 12, "Expected refresh reset state to advance the query generation")
    assertEqual(resetState.highlightIDs, [preservedID], "Expected refresh reset state to preserve the accepted page until replacement data arrives")
    assertEqual(resetState.availableBookTitles, ["Book Preserved"], "Expected refresh reset state to preserve existing book options")
    assertEqual(resetState.availableAuthors, ["Author Preserved"], "Expected refresh reset state to preserve existing author options")
    assertEqual(resetState.selectedHighlightIDs, [preservedID], "Expected refresh reset state to preserve current selection")
}

private func testOnlySortChangesSkipFilterOptionReloads() {
    assertEqual(
        QuotesListViewTestProbe.reloadsFilterOptions(for: "sortChanged"),
        false,
        "Expected sort changes to skip filter-option reloads"
    )

    let optionReloadReasons = [
        "appear",
        "refresh",
        "searchChanged",
        "bookFilterChanged",
        "authorFilterChanged",
        "bookStatusChanged",
        "sourceFilterChanged",
        "libraryChanged"
    ]

    for reason in optionReloadReasons {
        assertEqual(
            QuotesListViewTestProbe.reloadsFilterOptions(for: reason),
            true,
            "Expected \(reason) to continue reloading filter options"
        )
    }
}

private func testGenerationFreshnessGateRejectsStaleResults() {
    assertTrue(
        QuotesListViewTestProbe.shouldAcceptAsyncResult(
            capturedGeneration: 5,
            activeQueryGeneration: 5
        ),
        "Expected matching generations to remain acceptable"
    )
    assertTrue(
        !QuotesListViewTestProbe.shouldAcceptAsyncResult(
            capturedGeneration: 5,
            activeQueryGeneration: 6
        ),
        "Expected stale generations to be rejected before mutating UI state"
    )
    assertTrue(
        !QuotesListViewTestProbe.shouldAcceptAsyncResult(
            capturedGeneration: 6,
            activeQueryGeneration: 5
        ),
        "Expected mismatched generations to be rejected regardless of ordering"
    )
}

@main
struct VerifyT127AMain {
    static func main() {
        testRefreshResetStateAdvancesGenerationWhilePreservingResolvedSnapshot()
        testOnlySortChangesSkipFilterOptionReloads()
        testGenerationFreshnessGateRejectsStaleResults()
        print("verify_t127a_main passed")
    }
}
