import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t120a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail(message)
    }
}

private func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        fail(message)
    }
}

private func makeHighlight(
    id: UUID,
    bookId: UUID? = nil,
    quoteText: String,
    bookTitle: String,
    author: String,
    location: String? = nil,
    dateAdded: Date? = Date(timeIntervalSince1970: 100),
    lastShownAt: Date? = Date(timeIntervalSince1970: 200),
    isEnabled: Bool = true
) -> Highlight {
    Highlight(
        id: id,
        bookId: bookId,
        quoteText: quoteText,
        bookTitle: bookTitle,
        author: author,
        location: location,
        dateAdded: dateAdded,
        lastShownAt: lastShownAt,
        isEnabled: isEnabled
    )
}

@MainActor
private func testQuoteSaveErrorPresentationCopy() {
    assertEqual(
        QuoteEditViewTestProbe.errorMessage(for: .duplicateQuote),
        "A matching quote already exists in your library.",
        "Expected duplicate quote error message to stay user-facing"
    )

    assertEqual(
        QuoteEditViewTestProbe.errorRecoverySuggestion(for: .duplicateQuote),
        "Edit the quote details or cancel to keep the original saved quote unchanged." as String?,
        "Expected duplicate quote recovery guidance to explain the non-mutating path"
    )
}

@MainActor
private func testUpdateQuoteRefreshesOnlyAfterSuccessfulSave() throws {
    let original = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001201")!,
        quoteText: "Original quote",
        bookTitle: "Original Book",
        author: "Original Author",
        location: "Loc 10"
    )
    let request = QuoteEditSaveRequest(
        bookId: UUID(uuidString: "00000000-0000-0000-0000-000000001202")!,
        quoteText: "Updated quote",
        bookTitle: "Updated Book",
        author: "Updated Author",
        location: "Loc 11"
    )

    var savedHighlight: Highlight?
    var fetchAllBooksCalls = 0
    var fetchTotalHighlightCountCalls = 0

    let appState = AppState(
        totalHighlightCount: nil,
        books: nil,
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/wallpaper.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        updateHighlight: { highlight in
            savedHighlight = highlight
        },
        fetchAllBooks: {
            fetchAllBooksCalls += 1
            return []
        },
        fetchTotalHighlightCount: {
            fetchTotalHighlightCountCalls += 1
            return 42
        }
    )

    let initialFetchAllBooksCalls = fetchAllBooksCalls
    let initialFetchTotalHighlightCountCalls = fetchTotalHighlightCountCalls

    let updated = try appState.updateQuote(original, with: request)

    assertEqual(savedHighlight, updated, "Expected app state to pass the updated highlight to persistence")
    assertEqual(updated.id, original.id, "Expected quote edit save to preserve highlight identity")
    assertEqual(updated.dateAdded, original.dateAdded, "Expected quote edit save to preserve dateAdded")
    assertEqual(updated.lastShownAt, original.lastShownAt, "Expected quote edit save to preserve lastShownAt")
    assertEqual(updated.quoteText, request.quoteText, "Expected quote text to update on successful save")
    assertEqual(updated.bookTitle, request.bookTitle, "Expected book title to update on successful save")
    assertEqual(updated.author, request.author, "Expected author to update on successful save")
    assertEqual(updated.location, request.location, "Expected location to update on successful save")
    assertEqual(updated.bookId, request.bookId, "Expected linked book to update on successful save")
    assertEqual(
        fetchAllBooksCalls,
        initialFetchAllBooksCalls + 1,
        "Expected successful quote save to refresh books exactly once"
    )
    assertEqual(
        fetchTotalHighlightCountCalls,
        initialFetchTotalHighlightCountCalls + 1,
        "Expected successful quote save to refresh total highlight count exactly once"
    )
}

@MainActor
private func testUpdateQuoteDoesNotRefreshAfterDuplicateSaveFailure() {
    let original = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001301")!,
        quoteText: "Original quote",
        bookTitle: "Original Book",
        author: "Original Author",
        location: "Loc 20"
    )
    let request = QuoteEditSaveRequest(
        bookId: nil,
        quoteText: "Conflicting quote",
        bookTitle: "Conflicting Book",
        author: "Conflicting Author",
        location: "Loc 21"
    )

    var fetchAllBooksCalls = 0
    var fetchTotalHighlightCountCalls = 0
    var updateAttemptCount = 0

    let appState = AppState(
        totalHighlightCount: nil,
        books: nil,
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/wallpaper.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        updateHighlight: { _ in
            updateAttemptCount += 1
            throw AppState.QuoteSaveError.duplicateQuote
        },
        fetchAllBooks: {
            fetchAllBooksCalls += 1
            return []
        },
        fetchTotalHighlightCount: {
            fetchTotalHighlightCountCalls += 1
            return 42
        }
    )

    let initialFetchAllBooksCalls = fetchAllBooksCalls
    let initialFetchTotalHighlightCountCalls = fetchTotalHighlightCountCalls

    do {
        _ = try appState.updateQuote(original, with: request)
        fail("Expected duplicate quote save to throw")
    } catch let error as AppState.QuoteSaveError {
        assertEqual(error, .duplicateQuote, "Expected duplicate quote save to surface the recoverable duplicate error")
    } catch {
        fail("Expected duplicate quote save to throw AppState.QuoteSaveError, got \(error)")
    }

    assertEqual(updateAttemptCount, 1, "Expected duplicate quote save to attempt persistence exactly once")
    assertEqual(
        fetchAllBooksCalls,
        initialFetchAllBooksCalls,
        "Expected duplicate quote save failure to skip books refresh"
    )
    assertEqual(
        fetchTotalHighlightCountCalls,
        initialFetchTotalHighlightCountCalls,
        "Expected duplicate quote save failure to skip highlight-count refresh"
    )
    assertTrue(original.quoteText == "Original quote", "Expected original stored quote snapshot to stay unchanged in memory")
}

Task { @MainActor in
    testQuoteSaveErrorPresentationCopy()

    do {
        try testUpdateQuoteRefreshesOnlyAfterSuccessfulSave()
    } catch {
        fail("Expected successful quote save test to pass: \(error)")
    }

    testUpdateQuoteDoesNotRefreshAfterDuplicateSaveFailure()
    print("verify_t120a_main passed")
    exit(0)
}

RunLoop.main.run()
