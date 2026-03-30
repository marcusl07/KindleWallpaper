import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t80_main failed: \(message)\n", stderr)
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
    id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!,
    lastShownAt: Date? = Date(timeIntervalSince1970: 300),
    isEnabled: Bool = true
) -> Highlight {
    Highlight(
        id: id,
        bookId: UUID(uuidString: "00000000-0000-0000-0000-000000000ABC"),
        quoteText: "A quote worth rotating.",
        bookTitle: "Book",
        author: "Author",
        location: "Loc 42",
        dateAdded: Date(timeIntervalSince1970: 200),
        lastShownAt: lastShownAt,
        isEnabled: isEnabled
    )
}

@MainActor
private func testAppStateForwardsHighlightToggleRequests() {
    let expectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000777")!
    var recordedCalls: [(UUID, Bool)] = []

    let appState = AppState(
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/verify_t80.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        setHighlightEnabled: { id, enabled in
            recordedCalls.append((id, enabled))
        }
    )

    appState.setHighlightEnabled(id: expectedID, enabled: false)
    appState.setHighlightEnabled(id: expectedID, enabled: true)

    assertEqual(recordedCalls.count, 2, "Expected app state to forward both highlight toggle requests")
    assertEqual(recordedCalls[0].0, expectedID, "Expected disable request to preserve the highlight id")
    assertEqual(recordedCalls[0].1, false, "Expected first request to disable the highlight")
    assertEqual(recordedCalls[1].1, true, "Expected second request to re-enable the highlight")
}

private func testQuoteDetailProbeReportsExplicitLabelsAndStatuses() {
    assertEqual(
        QuoteDetailViewTestProbe.toggleButtonTitle(isEnabled: true),
        "Disable from Rotation",
        "Expected enabled quotes to show the disable action"
    )
    assertEqual(
        QuoteDetailViewTestProbe.toggleButtonTitle(isEnabled: false),
        "Enable for Rotation",
        "Expected disabled quotes to show the enable action"
    )
    assertEqual(
        QuoteDetailViewTestProbe.effectiveRotationStatusText(quoteIsEnabled: true, bookIsEnabled: true),
        "Yes",
        "Expected enabled quote in enabled book to be included in rotation"
    )
    assertEqual(
        QuoteDetailViewTestProbe.effectiveRotationStatusText(quoteIsEnabled: true, bookIsEnabled: false),
        "No (book disabled)",
        "Expected disabled parent books to keep the quote out of rotation"
    )
    assertEqual(
        QuoteDetailViewTestProbe.effectiveRotationStatusText(quoteIsEnabled: false, bookIsEnabled: true),
        "No",
        "Expected disabled quotes to be excluded from rotation"
    )
    assertEqual(
        QuoteDetailViewTestProbe.toggleStatusMessage(isEnabled: true, bookIsEnabled: false),
        "Quote enabled. It will rotate once its book is enabled.",
        "Expected re-enable messaging to acknowledge disabled books"
    )
    assertEqual(
        QuoteDetailViewTestProbe.toggleStatusMessage(isEnabled: false, bookIsEnabled: true),
        "Quote removed from rotation.",
        "Expected disable messaging to be explicit"
    )
}

private func testUpdatedHighlightClearsLastShownWhenReEnabled() {
    let enabledHighlight = QuoteDetailViewTestProbe.updatedHighlight(
        makeHighlight(lastShownAt: Date(timeIntervalSince1970: 600), isEnabled: false),
        isEnabled: true
    )
    let disabledHighlight = QuoteDetailViewTestProbe.updatedHighlight(
        makeHighlight(lastShownAt: Date(timeIntervalSince1970: 700), isEnabled: true),
        isEnabled: false
    )

    assertTrue(enabledHighlight.lastShownAt == nil, "Expected re-enabled highlights to reset lastShownAt")
    assertEqual(disabledHighlight.lastShownAt, Date(timeIntervalSince1970: 700), "Expected disabling to preserve lastShownAt")
    assertTrue(enabledHighlight.isEnabled, "Expected re-enabled highlight copy to be enabled")
    assertTrue(!disabledHighlight.isEnabled, "Expected disabled highlight copy to be disabled")
}

MainActor.assumeIsolated {
    testAppStateForwardsHighlightToggleRequests()
    testQuoteDetailProbeReportsExplicitLabelsAndStatuses()
    testUpdatedHighlightClearsLastShownWhenReEnabled()
}

print("verify_t80_main passed")
