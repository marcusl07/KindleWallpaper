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

testViewTitleAndDraftInitialization()
testSaveRequiresNonBlankQuoteText()
testMatchingUsesTrimmedCaseInsensitiveBookIdentity()
testSaveRequestCanonicalizesMatchedBooksAndOptionalFields()

print("verify_t79_main passed")
