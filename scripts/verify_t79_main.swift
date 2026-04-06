import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t79_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail(message)
    }
}

private func assertNil<T>(_ value: T?, _ message: String) {
    if value != nil {
        fail(message)
    }
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func makeBook(id: UUID, title: String, author: String) -> Book {
    Book(
        id: id,
        title: title,
        author: author,
        isEnabled: true,
        highlightCount: 1
    )
}

private func makeHighlight(location: String?) -> Highlight {
    Highlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000099")!,
        bookId: UUID(uuidString: "00000000-0000-0000-0000-000000000199"),
        quoteText: "Stay with the original text.",
        bookTitle: "Deep Work",
        author: "Cal Newport",
        location: location,
        dateAdded: Date(timeIntervalSince1970: 100),
        lastShownAt: nil,
        isEnabled: true
    )
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T79-\(UUID().uuidString)"
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

private func testViewTitleAndDraftInitialization() {
    assertEqual(
        QuoteEditViewTestProbe.title(for: nil),
        "Add Quote",
        "Expected add mode to use the add title"
    )
    assertEqual(
        QuoteEditViewTestProbe.title(for: makeHighlight(location: "Loc 12")),
        "Edit Quote",
        "Expected edit mode to use the edit title"
    )

    let withLocation = QuoteEditViewTestProbe.draftSnapshot(from: makeHighlight(location: "Loc 12"))
    assertEqual(withLocation.quoteText, "Stay with the original text.", "Expected quote text to seed from the highlight")
    assertEqual(withLocation.bookTitle, "Deep Work", "Expected book title to seed from the highlight")
    assertEqual(withLocation.author, "Cal Newport", "Expected author to seed from the highlight")
    assertEqual(withLocation.location, "Loc 12", "Expected location to seed from the highlight")

    let withoutLocation = QuoteEditViewTestProbe.draftSnapshot(from: makeHighlight(location: nil))
    assertEqual(withoutLocation.location, "", "Expected nil locations to seed as an empty string")
}

private func testSaveRequiresNonBlankQuoteText() {
    assertTrue(
        !QuoteEditViewTestProbe.canSave(quoteText: " \n\t "),
        "Expected blank quote text to fail validation"
    )
    assertTrue(
        QuoteEditViewTestProbe.canSave(quoteText: " Keep the text "),
        "Expected non-blank quote text to pass validation"
    )
}

private func testMatchingUsesTrimmedCaseInsensitiveBookIdentity() {
    let matchingID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    let books = [
        makeBook(id: matchingID, title: "Clean Code", author: "Robert C. Martin"),
        makeBook(id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!, title: "Deep Work", author: "Cal Newport")
    ]

    assertEqual(
        QuoteEditViewTestProbe.matchedBookID(
            bookTitle: "  clean code ",
            author: " robert c. martin  ",
            books: books
        ),
        matchingID,
        "Expected trimmed, case-insensitive title and author to match an existing book"
    )
    assertNil(
        QuoteEditViewTestProbe.matchedBookID(
            bookTitle: "Clean Code",
            author: "",
            books: books
        ),
        "Expected book linking to require both title and author"
    )
}

private func testSaveRequestCanonicalizesMatchedBooksAndOptionalFields() {
    let matchingBook = makeBook(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
        title: "Clean Code",
        author: "Robert C. Martin"
    )
    let request = QuoteEditViewTestProbe.saveRequest(
        quoteText: "  Functions should do one thing.  ",
        bookTitle: " clean code ",
        author: " ROBERT C. MARTIN ",
        location: "  Loc 42  ",
        books: [matchingBook]
    )

    assertEqual(request.quoteText, "Functions should do one thing.", "Expected quote text to trim outer whitespace before saving")
    assertEqual(request.bookId, matchingBook.id, "Expected matching books to populate the linked book id")
    assertEqual(request.bookTitle, "Clean Code", "Expected matching books to use canonical book title casing")
    assertEqual(request.author, "Robert C. Martin", "Expected matching books to use canonical author casing")
    assertEqual(request.location, "Loc 42", "Expected location to trim outer whitespace before saving")

    let unmatchedRequest = QuoteEditViewTestProbe.saveRequest(
        quoteText: "  Independent quote  ",
        bookTitle: " ",
        author: "\n",
        location: "   ",
        books: [matchingBook]
    )

    assertNil(unmatchedRequest.bookId, "Expected unmatched quotes to remain unlinked")
    assertEqual(unmatchedRequest.bookTitle, "", "Expected blank book titles to save as empty strings")
    assertEqual(unmatchedRequest.author, "", "Expected blank authors to save as empty strings")
    assertNil(unmatchedRequest.location, "Expected blank locations to save as nil")
}

@MainActor
private func testUpdateQuotePreservesMetadataAndRefreshesLibraryState() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let originalHighlight = Highlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000501")!,
        bookId: UUID(uuidString: "00000000-0000-0000-0000-000000000502"),
        quoteText: "Original quote",
        bookTitle: "Original Book",
        author: "Original Author",
        location: "Loc 12",
        dateAdded: Date(timeIntervalSince1970: 501),
        lastShownAt: Date(timeIntervalSince1970: 777),
        isEnabled: false
    )
    let matchedBook = makeBook(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000503")!,
        title: "Clean Code",
        author: "Robert C. Martin"
    )

    var storedHighlight: Highlight?
    let totalHighlightCount = 3
    let refreshedBook = makeBook(
        id: matchedBook.id,
        title: matchedBook.title,
        author: matchedBook.author
    )

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: totalHighlightCount,
        books: [],
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        updateHighlight: { highlight in
            storedHighlight = highlight
        },
        fetchAllBooks: { [refreshedBook] },
        fetchTotalHighlightCount: { totalHighlightCount }
    )

    let request = QuoteEditViewTestProbe.saveRequest(
        quoteText: "  Updated quote text  ",
        bookTitle: " clean code ",
        author: " ROBERT C. MARTIN ",
        location: "  Loc 99  ",
        books: [matchedBook]
    )

    let updatedHighlight = appState.updateQuote(originalHighlight, with: request)

    guard let storedHighlight else {
        fail("Expected updateQuote to persist the updated highlight")
    }

    assertEqual(updatedHighlight.id, originalHighlight.id, "Expected editing to preserve highlight identity")
    assertEqual(updatedHighlight.dateAdded, originalHighlight.dateAdded, "Expected editing to preserve date added")
    assertEqual(updatedHighlight.lastShownAt, originalHighlight.lastShownAt, "Expected editing to preserve last shown date")
    assertEqual(updatedHighlight.isEnabled, originalHighlight.isEnabled, "Expected editing to preserve enabled state")
    assertEqual(updatedHighlight.bookId, matchedBook.id, "Expected editing to adopt the matched book id")
    assertEqual(updatedHighlight.quoteText, "Updated quote text", "Expected editing to trim quote text")
    assertEqual(updatedHighlight.bookTitle, "Clean Code", "Expected editing to canonicalize the matched title")
    assertEqual(updatedHighlight.author, "Robert C. Martin", "Expected editing to canonicalize the matched author")
    assertEqual(updatedHighlight.location, "Loc 99", "Expected editing to trim location")
    assertEqual(storedHighlight.id, updatedHighlight.id, "Expected persisted highlight id to match the returned value")
    assertEqual(storedHighlight.bookId, updatedHighlight.bookId, "Expected persisted highlight book link to match the returned value")
    assertEqual(storedHighlight.quoteText, updatedHighlight.quoteText, "Expected persisted quote text to match the returned value")
    assertEqual(appState.totalHighlightCount, totalHighlightCount, "Expected editing to leave total highlight count unchanged after refresh")
    assertEqual(appState.books.count, 1, "Expected editing to refresh books")
    assertEqual(appState.books.first?.id, refreshedBook.id, "Expected refreshed book identity to be published")
}

testViewTitleAndDraftInitialization()
testSaveRequiresNonBlankQuoteText()
testMatchingUsesTrimmedCaseInsensitiveBookIdentity()
testSaveRequestCanonicalizesMatchedBooksAndOptionalFields()
MainActor.assumeIsolated {
    testUpdateQuotePreservesMetadataAndRefreshesLibraryState()
}

print("verify_t79_main passed")
