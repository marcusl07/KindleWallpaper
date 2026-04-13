import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t124a_main failed: \(message)\n", stderr)
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
    quoteText: String,
    bookId: UUID? = nil,
    bookTitle: String? = nil,
    author: String? = nil,
    isEnabled: Bool = true
) -> Highlight {
    Highlight(
        id: id,
        bookId: bookId,
        quoteText: quoteText,
        bookTitle: bookTitle ?? "Book \(quoteText)",
        author: author ?? "Author \(quoteText)",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil,
        isEnabled: isEnabled
    )
}

private func makeBook(
    id: UUID,
    title: String,
    author: String,
    isEnabled: Bool,
    highlightCount: Int = 0
) -> Book {
    Book(
        id: id,
        title: title,
        author: author,
        isEnabled: isEnabled,
        highlightCount: highlightCount
    )
}

private func testMountedRefreshKeepsResolvedListAndSelectionMountedUntilReplacementArrives() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000001241")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000001242")!
    let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000001243")!
    let preservedHighlights = [
        makeHighlight(id: firstID, quoteText: "First"),
        makeHighlight(id: secondID, quoteText: "Second"),
        makeHighlight(id: thirdID, quoteText: "Third")
    ]

    let resetState = QuotesListViewTestProbe.refreshResetState(
        after: 4,
        preservingHighlights: preservedHighlights,
        totalMatchingHighlightCount: 3,
        availableBookTitles: ["Book First", "Book Second", "Book Third"],
        availableAuthors: ["Author First", "Author Second", "Author Third"],
        selectedHighlightIDs: [secondID]
    )
    let presentation = QuotesListViewTestProbe.presentationState(
        isLoadingHighlights: true,
        lastResolvedPrimaryContent: "list",
        totalHighlightCount: 3,
        displayedRowCount: resetState.highlightIDs.count
    )

    assertEqual(
        resetState.highlightIDs,
        [firstID, secondID, thirdID],
        "Expected mounted refresh resets to preserve the accepted list rows until replacement data arrives"
    )
    assertEqual(
        resetState.selectedHighlightIDs,
        [secondID],
        "Expected mounted refresh resets to preserve edit-mode selection while the overlay is shown"
    )
    assertEqual(
        presentation.primaryContent,
        "list",
        "Expected mounted refreshes from a resolved list to keep the list subtree mounted"
    )
    assertTrue(
        presentation.showsRefreshOverlay,
        "Expected mounted refreshes from a resolved list to use the loading overlay instead of remounting the spinner state"
    )
    assertEqual(
        QuotesListViewTestProbe.resultCountSummary(
            displayedCount: resetState.highlightIDs.count,
            totalCount: resetState.totalMatchingHighlightCount,
            hasActiveQuery: false,
            isEditing: true,
            selectedCount: resetState.selectedHighlightIDs.count
        ),
        "3 quotes • 1 selected",
        "Expected the mounted refresh path to preserve the existing edit-mode result summary"
    )
}

private func testMountedRefreshCanResolveIntoNoMatchesAndThenClearSelection() {
    let preservedID = UUID(uuidString: "00000000-0000-0000-0000-000000001244")!
    let resetState = QuotesListViewTestProbe.refreshResetState(
        after: 7,
        preservingHighlights: [
            makeHighlight(id: preservedID, quoteText: "Preserved")
        ],
        totalMatchingHighlightCount: 1,
        availableBookTitles: ["Book Preserved"],
        availableAuthors: ["Author Preserved"],
        selectedHighlightIDs: [preservedID]
    )
    let loadingPresentation = QuotesListViewTestProbe.presentationState(
        isLoadingHighlights: true,
        lastResolvedPrimaryContent: "list",
        totalHighlightCount: 12,
        displayedRowCount: resetState.highlightIDs.count
    )
    let settledPresentation = QuotesListViewTestProbe.presentationState(
        isLoadingHighlights: false,
        lastResolvedPrimaryContent: nil,
        totalHighlightCount: 12,
        displayedRowCount: 0
    )
    let reconciledSelection = QuotesListViewTestProbe.reconciledSelection(
        resetState.selectedHighlightIDs,
        validHighlightIDs: []
    )

    assertEqual(
        loadingPresentation.primaryContent,
        "list",
        "Expected the pre-refresh list to remain mounted while a no-matches replacement snapshot is loading"
    )
    assertTrue(
        loadingPresentation.showsRefreshOverlay,
        "Expected mounted refreshes to keep showing the loading overlay before the replacement snapshot is accepted"
    )
    assertEqual(
        settledPresentation.primaryContent,
        "noMatchingResults",
        "Expected the replacement snapshot to resolve to the no-matches state once loading completes"
    )
    assertTrue(
        !settledPresentation.showsRefreshOverlay,
        "Expected the loading overlay to disappear after the replacement no-matches snapshot is accepted"
    )
    assertEqual(
        reconciledSelection,
        [],
        "Expected edit-mode selection to clear only after the replacement no-matches snapshot is reconciled"
    )
    assertEqual(
        QuotesListViewTestProbe.resultCountSummary(
            displayedCount: 0,
            totalCount: 12,
            hasActiveQuery: true,
            isEditing: true,
            selectedCount: reconciledSelection.count
        ),
        "0 of 12 quotes • 0 selected",
        "Expected the no-matches edit-mode summary to remain consistent after mounted refresh reconciliation"
    )
}

private func testMountedRefreshLeavesFilteringAndPagingHelpersStableAfterAcceptance() {
    let enabledBookID = UUID(uuidString: "00000000-0000-0000-0000-000000001245")!
    let disabledBookID = UUID(uuidString: "00000000-0000-0000-0000-000000001246")!
    let firstAcceptedID = UUID(uuidString: "00000000-0000-0000-0000-000000001247")!
    let secondAcceptedID = UUID(uuidString: "00000000-0000-0000-0000-000000001248")!
    let appendedID = UUID(uuidString: "00000000-0000-0000-0000-000000001249")!
    let duplicateID = secondAcceptedID

    let books = [
        makeBook(id: enabledBookID, title: "Enabled Book", author: "A", isEnabled: true, highlightCount: 2),
        makeBook(id: disabledBookID, title: "Disabled Book", author: "B", isEnabled: false, highlightCount: 1)
    ]
    let acceptedHighlights = [
        makeHighlight(
            id: firstAcceptedID,
            quoteText: "Alpha",
            bookId: enabledBookID,
            bookTitle: "Enabled Book",
            author: "Author A",
            isEnabled: true
        ),
        makeHighlight(
            id: secondAcceptedID,
            quoteText: "Manual",
            bookId: enabledBookID,
            bookTitle: "Enabled Book",
            author: "Author A",
            isEnabled: true
        ),
        makeHighlight(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001250")!,
            quoteText: "Disabled",
            bookId: disabledBookID,
            bookTitle: "Disabled Book",
            author: "Author B",
            isEnabled: true
        )
    ]

    let filteredIDs = QuotesListViewTestProbe.displayedHighlightIDs(
        from: acceptedHighlights,
        searchText: "",
        sortMode: .alphabeticalByBook,
        books: books,
        selectedBookTitle: "Enabled Book",
        selectedAuthor: "Author A",
        bookStatus: .enabledBooksOnly,
        source: .allQuotes
    )
    let appendResult = QuotesListViewTestProbe.appendPage(
        existingHighlights: Array(acceptedHighlights.prefix(2)),
        nextPage: [
            makeHighlight(
                id: appendedID,
                quoteText: "Zulu",
                bookId: enabledBookID,
                bookTitle: "Enabled Book",
                author: "Author A",
                isEnabled: true
            ),
            makeHighlight(
                id: duplicateID,
                quoteText: "Manual",
                bookId: enabledBookID,
                bookTitle: "Enabled Book",
                author: "Author A",
                isEnabled: true
            )
        ],
        totalMatchingHighlightCount: 3
    )

    assertEqual(
        filteredIDs,
        [firstAcceptedID, secondAcceptedID],
        "Expected the accepted replacement snapshot to keep quotes filtering stable after the mounted refresh path settles"
    )
    assertEqual(
        appendResult.highlightIDs,
        [firstAcceptedID, secondAcceptedID, appendedID],
        "Expected paging after a mounted refresh to append only new rows while preserving the accepted order"
    )
    assertTrue(
        !appendResult.hasMoreHighlights,
        "Expected paging after a mounted refresh to stop once the accepted total count is reached"
    )
}

@main
struct VerifyT124AMain {
    static func main() {
        testMountedRefreshKeepsResolvedListAndSelectionMountedUntilReplacementArrives()
        testMountedRefreshCanResolveIntoNoMatchesAndThenClearSelection()
        testMountedRefreshLeavesFilteringAndPagingHelpersStableAfterAcceptance()
        print("verify_t124a_main passed")
    }
}
