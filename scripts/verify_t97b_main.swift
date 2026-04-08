import Foundation

@main
struct VerifyT97BMain {
    static func main() {
        testStableIdentityUsesFullNormalizedQuoteText()
        testImportSkipsTombstonedHighlights()
        print("verify_t97b_main passed")
    }

    private static func testStableIdentityUsesFullNormalizedQuoteText() {
        let first = ImportStableQuoteIdentityKeyBuilder.makeKey(
            bookTitle: " Deep   Work ",
            author: "Cal   Newport",
            location: " 12-13 ",
            quoteText: "A long quote with spacing.\n\nAnd a second sentence."
        )
        let normalizedMatch = ImportStableQuoteIdentityKeyBuilder.makeKey(
            bookTitle: "Deep Work",
            author: "Cal Newport",
            location: "12-13",
            quoteText: "A long quote with spacing. And a second sentence."
        )
        let changedTail = ImportStableQuoteIdentityKeyBuilder.makeKey(
            bookTitle: "Deep Work",
            author: "Cal Newport",
            location: "12-13",
            quoteText: "A long quote with spacing. And a different sentence."
        )

        assertEqual(first, normalizedMatch, "Stable quote identity should normalize whitespace consistently")
        assertNotEqual(first, changedTail, "Stable quote identity should include the full normalized quote text")
    }

    private static func testImportSkipsTombstonedHighlights() {
        let fileURL = writeTemporaryFile(named: "verify_t97b_import.txt", contents: "contents")
        let parsedBookID = UUID()
        let storedBookID = UUID()

        let parsedBook = Book(
            id: parsedBookID,
            title: "Deep Work",
            author: "Cal Newport",
            isEnabled: true,
            highlightCount: 2
        )
        let deletedHighlight = Highlight(
            id: UUID(),
            bookId: parsedBookID,
            quoteText: "Deleted quote",
            bookTitle: "Deep Work",
            author: "Cal Newport",
            location: "12-13",
            dateAdded: nil,
            lastShownAt: nil
        )
        let liveHighlight = Highlight(
            id: UUID(),
            bookId: parsedBookID,
            quoteText: "Fresh quote",
            bookTitle: "Deep Work",
            author: "Cal Newport",
            location: "14-15",
            dateAdded: nil,
            lastShownAt: nil
        )

        var insertedHighlights: [Highlight] = []
        var totalCountCalls = 0

        let coordinator = ImportCoordinator(
            parseClippings: { _ in
                ClippingsParser.ParseResult(
                    highlights: [deletedHighlight, liveHighlight],
                    books: [parsedBook],
                    parseErrorCount: 0,
                    skippedEntryCount: 0,
                    warningMessages: [],
                    error: nil
                )
            },
            upsertBook: { _ in storedBookID },
            highlightHasTombstone: { highlight in
                ImportStableQuoteIdentityKeyBuilder.makeKey(
                    bookTitle: highlight.bookTitle,
                    author: highlight.author,
                    location: highlight.location,
                    quoteText: highlight.quoteText
                ) == ImportStableQuoteIdentityKeyBuilder.makeKey(
                    bookTitle: "Deep Work",
                    author: "Cal Newport",
                    location: "12-13",
                    quoteText: "Deleted quote"
                )
            },
            insertHighlightIfNew: { highlight in
                insertedHighlights.append(highlight)
            },
            totalHighlightCount: {
                totalCountCalls += 1
                return totalCountCalls == 1 ? 7 : 8
            }
        )

        let result = coordinator.importFile(at: fileURL)

        assertEqual(result.newHighlightCount, 1, "Tombstoned highlights should not contribute to imported count")
        assertEqual(insertedHighlights.count, 1, "Tombstoned highlights should be skipped before insertion")
        assertEqual(insertedHighlights.first?.quoteText, "Fresh quote", "Non-tombstoned highlights should still import")
        assertEqual(insertedHighlights.first?.bookId, storedBookID, "Imported highlights should still map to persisted book IDs")
    }
}

private func writeTemporaryFile(named fileName: String, contents: String) -> URL {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent(fileName)
    let directoryURL = fileURL.deletingLastPathComponent()

    do {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    } catch {
        fail("Failed to create temporary file for verification: \(error)")
    }
}

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message)\nExpected: \(expected)\nActual:   \(actual)\n", stderr)
        exit(1)
    }
}

private func assertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    guard lhs != rhs else {
        fputs("Assertion failed: \(message)\nBoth values were: \(lhs)\n", stderr)
        exit(1)
    }
}

private func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}
