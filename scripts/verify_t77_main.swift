import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t77_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail(message)
    }
}

private func makeHighlight(
    id: UUID,
    bookId: UUID?,
    quoteText: String,
    bookTitle: String,
    author: String,
    dateAdded: Date? = nil
) -> Highlight {
    Highlight(
        id: id,
        bookId: bookId,
        quoteText: quoteText,
        bookTitle: bookTitle,
        author: author,
        location: nil,
        dateAdded: dateAdded,
        lastShownAt: nil,
        isEnabled: true
    )
}

private func makeBook(
    id: UUID,
    title: String,
    author: String,
    isEnabled: Bool
) -> Book {
    Book(
        id: id,
        title: title,
        author: author,
        isEnabled: isEnabled,
        highlightCount: 1
    )
}

private func testBookAndAuthorFiltersComposeWithSearch() {
    let enabledBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    let disabledBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    let highlights = [
        makeHighlight(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
            bookId: enabledBookID,
            quoteText: "Build in public.",
            bookTitle: "Build",
            author: "Ava",
            dateAdded: Date(timeIntervalSince1970: 200)
        ),
        makeHighlight(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            bookId: enabledBookID,
            quoteText: "Build resilient systems.",
            bookTitle: "Build",
            author: "Ava",
            dateAdded: Date(timeIntervalSince1970: 100)
        ),
        makeHighlight(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000203")!,
            bookId: disabledBookID,
            quoteText: "Measure twice.",
            bookTitle: "Measure",
            author: "Ben",
            dateAdded: Date(timeIntervalSince1970: 300)
        )
    ]
    let books = [
        makeBook(id: enabledBookID, title: "Build", author: "Ava", isEnabled: true),
        makeBook(id: disabledBookID, title: "Measure", author: "Ben", isEnabled: false)
    ]

    assertEqual(
        QuotesListViewTestProbe.displayedHighlightIDs(
            from: highlights,
            searchText: "resilient",
            sortMode: .mostRecentlyAdded,
            books: books,
            selectedBookTitle: "Build",
            selectedAuthor: "Ava"
        ),
        [UUID(uuidString: "00000000-0000-0000-0000-000000000202")!],
        "Expected book and author filters to compose with search text"
    )
}

private func testBookStatusFiltersUseBookEnabledState() {
    let enabledBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000301")!
    let disabledBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000302")!

    let enabledHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!,
        bookId: enabledBookID,
        quoteText: "Enabled quote",
        bookTitle: "Enabled Book",
        author: "Ada"
    )
    let disabledHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!,
        bookId: disabledBookID,
        quoteText: "Disabled quote",
        bookTitle: "Disabled Book",
        author: "Bea"
    )
    let manualHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
        bookId: nil,
        quoteText: "Manual quote",
        bookTitle: "Standalone",
        author: "Cara"
    )

    let books = [
        makeBook(id: enabledBookID, title: "Enabled Book", author: "Ada", isEnabled: true),
        makeBook(id: disabledBookID, title: "Disabled Book", author: "Bea", isEnabled: false)
    ]

    assertEqual(
        QuotesListViewTestProbe.displayedHighlightIDs(
            from: [enabledHighlight, disabledHighlight, manualHighlight],
            searchText: "",
            sortMode: .alphabeticalByBook,
            books: books,
            bookStatus: .enabledBooksOnly
        ),
        [enabledHighlight.id],
        "Expected enabled-books filter to keep only quotes linked to enabled books"
    )

    assertEqual(
        QuotesListViewTestProbe.displayedHighlightIDs(
            from: [enabledHighlight, disabledHighlight, manualHighlight],
            searchText: "",
            sortMode: .alphabeticalByBook,
            books: books,
            bookStatus: .disabledBooksOnly
        ),
        [disabledHighlight.id],
        "Expected disabled-books filter to keep only quotes linked to disabled books"
    )
}

private func testManualOnlyFilterExcludesLinkedQuotes() {
    let linkedBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000501")!
    let manualHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000601")!,
        bookId: nil,
        quoteText: "Typed by hand",
        bookTitle: "Notebook",
        author: "Dana",
        dateAdded: Date(timeIntervalSince1970: 10)
    )
    let linkedHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000602")!,
        bookId: linkedBookID,
        quoteText: "Imported from Kindle",
        bookTitle: "Reader",
        author: "Eli",
        dateAdded: Date(timeIntervalSince1970: 20)
    )

    assertEqual(
        QuotesListViewTestProbe.displayedHighlightIDs(
            from: [linkedHighlight, manualHighlight],
            searchText: "",
            sortMode: .mostRecentlyAdded,
            source: .manualOnly
        ),
        [manualHighlight.id],
        "Expected manual-only filter to keep only quotes without a linked book"
    )
}

private func testFilterOptionListsAreUniqueAndSorted() {
    let highlights = [
        makeHighlight(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
            bookId: nil,
            quoteText: "One",
            bookTitle: "beta",
            author: "zoe"
        ),
        makeHighlight(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000702")!,
            bookId: nil,
            quoteText: "Two",
            bookTitle: "Alpha",
            author: "Ava"
        ),
        makeHighlight(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000703")!,
            bookId: nil,
            quoteText: "Three",
            bookTitle: " alpha ",
            author: "ava "
        )
    ]

    assertEqual(
        QuotesListViewTestProbe.availableBookTitles(from: highlights),
        ["Alpha", "beta"],
        "Expected book filter options to dedupe and sort normalized titles"
    )
    assertEqual(
        QuotesListViewTestProbe.availableAuthors(from: highlights),
        ["Ava", "zoe"],
        "Expected author filter options to dedupe and sort normalized authors"
    )
}

testBookAndAuthorFiltersComposeWithSearch()
testBookStatusFiltersUseBookEnabledState()
testManualOnlyFilterExcludesLinkedQuotes()
testFilterOptionListsAreUniqueAndSorted()

print("verify_t77_main passed")
