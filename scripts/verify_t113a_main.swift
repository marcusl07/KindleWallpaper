import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t113a_main failed: \(message)\n", stderr)
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

private func testFilteringPreservesIncomingOrderWithoutResorting() {
    let first = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001101")!,
        bookId: nil,
        quoteText: "Gamma insight",
        bookTitle: "Gamma",
        author: "Ava",
        dateAdded: Date(timeIntervalSince1970: 100)
    )
    let second = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001102")!,
        bookId: nil,
        quoteText: "Alpha insight",
        bookTitle: "Alpha",
        author: "Ava",
        dateAdded: Date(timeIntervalSince1970: 300)
    )
    let third = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001103")!,
        bookId: nil,
        quoteText: "Beta insight",
        bookTitle: "Beta",
        author: "Ava",
        dateAdded: Date(timeIntervalSince1970: 200)
    )

    assertEqual(
        QuotesListViewTestProbe.filteredHighlightIDs(
            from: [first, second, third],
            searchText: "insight"
        ),
        [first.id, second.id, third.id],
        "Expected filtered highlights to preserve incoming order"
    )
}

private func testFilteringKeepsRelativeOrderOfMatches() {
    let enabledBookID = UUID(uuidString: "00000000-0000-0000-0000-000000001201")!
    let disabledBookID = UUID(uuidString: "00000000-0000-0000-0000-000000001202")!

    let includedFirst = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001211")!,
        bookId: enabledBookID,
        quoteText: "Keep this first",
        bookTitle: "Book",
        author: "Author"
    )
    let excluded = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001212")!,
        bookId: disabledBookID,
        quoteText: "Filter me out",
        bookTitle: "Book",
        author: "Author"
    )
    let includedSecond = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001213")!,
        bookId: enabledBookID,
        quoteText: "Keep this second",
        bookTitle: "Book",
        author: "Author"
    )

    let books = [
        makeBook(id: enabledBookID, title: "Book", author: "Author", isEnabled: true),
        makeBook(id: disabledBookID, title: "Book", author: "Author", isEnabled: false)
    ]

    assertEqual(
        QuotesListViewTestProbe.filteredHighlightIDs(
            from: [includedFirst, excluded, includedSecond],
            searchText: "keep",
            books: books,
            bookStatus: .enabledBooksOnly
        ),
        [includedFirst.id, includedSecond.id],
        "Expected filters to keep the original relative order of matching highlights"
    )
}

testFilteringPreservesIncomingOrderWithoutResorting()
testFilteringKeepsRelativeOrderOfMatches()

print("verify_t113a_main passed")
