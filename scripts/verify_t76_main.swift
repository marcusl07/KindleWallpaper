import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t76_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail(message)
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
    bookTitle: String,
    author: String,
    dateAdded: Date?
) -> Highlight {
    Highlight(
        id: id,
        bookId: UUID(),
        quoteText: quoteText,
        bookTitle: bookTitle,
        author: author,
        location: nil,
        dateAdded: dateAdded,
        lastShownAt: nil,
        isEnabled: true
    )
}

private func testSearchMatchesQuoteBookAndAuthor() {
    let recent = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        quoteText: "Stay hungry, stay foolish.",
        bookTitle: "Steve Jobs",
        author: "Walter Isaacson",
        dateAdded: Date(timeIntervalSince1970: 300)
    )
    let older = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!,
        quoteText: "Ship small increments.",
        bookTitle: "The Pragmatic Programmer",
        author: "Andy Hunt",
        dateAdded: Date(timeIntervalSince1970: 200)
    )
    let nilDate = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!,
        quoteText: "Simplicity is prerequisite for reliability.",
        bookTitle: "Clean Architecture",
        author: "John Ousterhout",
        dateAdded: nil
    )
    let highlights = [older, nilDate, recent]

    assertEqual(
        QuotesListViewTestProbe.displayedHighlightIDs(
            from: highlights,
            searchText: "foolish",
            sortMode: .mostRecentlyAdded
        ),
        [recent.id],
        "Expected quote text search to match the quote body"
    )
    assertEqual(
        QuotesListViewTestProbe.displayedHighlightIDs(
            from: highlights,
            searchText: "pragmatic",
            sortMode: .mostRecentlyAdded
        ),
        [older.id],
        "Expected search to match book titles case-insensitively"
    )
    assertEqual(
        QuotesListViewTestProbe.displayedHighlightIDs(
            from: highlights,
            searchText: "ousterhout",
            sortMode: .mostRecentlyAdded
        ),
        [nilDate.id],
        "Expected search to match authors"
    )
}

private func testMostRecentSortPlacesNewestFirstAndNilDatesLast() {
    let newest = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000011")!,
        quoteText: "Newest",
        bookTitle: "Gamma",
        author: "Author C",
        dateAdded: Date(timeIntervalSince1970: 500)
    )
    let older = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000012")!,
        quoteText: "Older",
        bookTitle: "Alpha",
        author: "Author A",
        dateAdded: Date(timeIntervalSince1970: 200)
    )
    let undated = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000013")!,
        quoteText: "Undated",
        bookTitle: "Beta",
        author: "Author B",
        dateAdded: nil
    )

    assertEqual(
        QuotesListViewTestProbe.displayedHighlightIDs(
            from: [older, undated, newest],
            searchText: "",
            sortMode: .mostRecentlyAdded
        ),
        [newest.id, older.id, undated.id],
        "Expected most recent sort to order by descending dateAdded with nil dates last"
    )
}

private func testAlphabeticalSortUsesBookThenAuthorThenQuote() {
    let zeta = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000021")!,
        quoteText: "Zeta quote",
        bookTitle: "Zeta",
        author: "Author Z",
        dateAdded: nil
    )
    let alphaB = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000022")!,
        quoteText: "Second",
        bookTitle: "Alpha",
        author: "Author B",
        dateAdded: nil
    )
    let alphaA = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000023")!,
        quoteText: "First",
        bookTitle: "Alpha",
        author: "Author A",
        dateAdded: nil
    )

    assertEqual(
        QuotesListViewTestProbe.displayedHighlightIDs(
            from: [zeta, alphaB, alphaA],
            searchText: "",
            sortMode: .alphabeticalByBook
        ),
        [alphaA.id, alphaB.id, zeta.id],
        "Expected alphabetical sort to order by book title, then author, then quote"
    )
}

private func testPresentationTextNormalizesWhitespaceAndFallbacks() {
    let blankMetadataHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000031")!,
        quoteText: "  \n  ",
        bookTitle: " ",
        author: "\t",
        dateAdded: nil
    )

    assertEqual(
        QuotesListViewTestProbe.previewText(for: "  Keep   things\nsimple.  "),
        "Keep things simple.",
        "Expected preview text to collapse repeated whitespace"
    )
    assertEqual(
        QuotesListViewTestProbe.previewText(for: blankMetadataHighlight.quoteText),
        "Untitled quote",
        "Expected blank quote text to fall back to a placeholder"
    )
    assertEqual(
        QuotesListViewTestProbe.bookTitleText(for: blankMetadataHighlight),
        "Unknown Book",
        "Expected blank book titles to fall back to a placeholder"
    )
    assertEqual(
        QuotesListViewTestProbe.authorText(for: blankMetadataHighlight),
        "Unknown Author",
        "Expected blank authors to fall back to a placeholder"
    )
}

testSearchMatchesQuoteBookAndAuthor()
testMostRecentSortPlacesNewestFirstAndNilDatesLast()
testAlphabeticalSortUsesBookThenAuthorThenQuote()
testPresentationTextNormalizesWhitespaceAndFallbacks()

print("verify_t76_main passed")
