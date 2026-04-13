import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t123a_main failed: \(message)\n", stderr)
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

private func assertFalse(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
        fail(message)
    }
}

private func testInitialLoadUsesSpinnerOnlyPresentation() {
    let presentation = QuotesListViewTestProbe.presentationState(
        isLoadingHighlights: true,
        lastResolvedPrimaryContent: nil,
        totalHighlightCount: 0,
        displayedRowCount: 0
    )

    assertEqual(
        presentation.primaryContent,
        "initialLoading",
        "Expected first-load quote refreshes without resolved content to use the standalone loading state"
    )
    assertFalse(
        presentation.showsRefreshOverlay,
        "Expected first-load quote refreshes without resolved content to avoid the refresh overlay"
    )
}

private func testRefreshAfterResolvedListUsesOverlay() {
    let presentation = QuotesListViewTestProbe.presentationState(
        isLoadingHighlights: true,
        lastResolvedPrimaryContent: "list",
        totalHighlightCount: 0,
        displayedRowCount: 0
    )

    assertEqual(
        presentation.primaryContent,
        "list",
        "Expected quote refreshes with preserved rows to keep rendering the list content"
    )
    assertTrue(
        presentation.showsRefreshOverlay,
        "Expected quote refreshes with preserved rows to show a loading overlay"
    )
}

private func testRefreshAfterResolvedEmptyStatesUsesOverlay() {
    let libraryEmptyPresentation = QuotesListViewTestProbe.presentationState(
        isLoadingHighlights: true,
        lastResolvedPrimaryContent: "libraryEmpty",
        totalHighlightCount: 5,
        displayedRowCount: 3
    )
    let noMatchesPresentation = QuotesListViewTestProbe.presentationState(
        isLoadingHighlights: true,
        lastResolvedPrimaryContent: "noMatchingResults",
        totalHighlightCount: 0,
        displayedRowCount: 0
    )

    assertEqual(
        libraryEmptyPresentation.primaryContent,
        "libraryEmpty",
        "Expected refreshes after an empty library resolution to keep the library-empty subtree mounted"
    )
    assertTrue(
        libraryEmptyPresentation.showsRefreshOverlay,
        "Expected refreshes after an empty library resolution to show the loading overlay"
    )
    assertEqual(
        noMatchesPresentation.primaryContent,
        "noMatchingResults",
        "Expected refreshes after a no-matches resolution to keep the no-matches subtree mounted"
    )
    assertTrue(
        noMatchesPresentation.showsRefreshOverlay,
        "Expected refreshes after a no-matches resolution to show the loading overlay"
    )
}

private func testResolvedContentUsesLiveCountsAfterRefreshCompletes() {
    assertEqual(
        QuotesListViewTestProbe.resolvedPrimaryContent(totalHighlightCount: 0, displayedRowCount: 0),
        "libraryEmpty",
        "Expected zero library highlights to resolve to the library-empty state"
    )
    assertEqual(
        QuotesListViewTestProbe.resolvedPrimaryContent(totalHighlightCount: 12, displayedRowCount: 0),
        "noMatchingResults",
        "Expected an empty filtered snapshot from a non-empty library to resolve to the no-matching-results state"
    )
    assertEqual(
        QuotesListViewTestProbe.resolvedPrimaryContent(totalHighlightCount: 12, displayedRowCount: 4),
        "list",
        "Expected resolved quote rows to render the list state"
    )
}

testInitialLoadUsesSpinnerOnlyPresentation()
testRefreshAfterResolvedListUsesOverlay()
testRefreshAfterResolvedEmptyStatesUsesOverlay()
testResolvedContentUsesLiveCountsAfterRefreshCompletes()

print("verify_t123a_main passed")
