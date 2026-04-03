import Foundation

testManualDedupeKeyUsesTitleAndAuthor()
testLinkedAndManualDedupeKeysDoNotCollide()
testImportSkipsHighlightsWithoutBookMappings()
print("T73 main verification passed")

func testManualDedupeKeyUsesTitleAndAuthor() {
    let firstKey = DedupeKeyBuilder.makeKey(
        bookId: nil,
        bookTitle: "  Book Title ",
        author: "Author Name",
        location: "12-13",
        quoteText: "A memorable quote"
    )
    let matchingKey = DedupeKeyBuilder.makeKey(
        bookId: nil,
        bookTitle: "Book   Title",
        author: "Author   Name",
        location: "12-13",
        quoteText: "A memorable quote"
    )
    let differentBookKey = DedupeKeyBuilder.makeKey(
        bookId: nil,
        bookTitle: "Different Title",
        author: "Author Name",
        location: "12-13",
        quoteText: "A memorable quote"
    )

    assertEqual(firstKey, matchingKey, "Manual dedupe key should normalize title and author whitespace")
    assertNotEqual(firstKey, differentBookKey, "Manual dedupe key should distinguish different manual quote attribution")
}

func testLinkedAndManualDedupeKeysDoNotCollide() {
    let linkedBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000123")!
    let linkedKey = DedupeKeyBuilder.makeKey(
        bookId: linkedBookID,
        location: "22-23",
        quoteText: "Same quote"
    )
    let manualKey = DedupeKeyBuilder.makeKey(
        bookId: nil,
        bookTitle: "Same Book",
        author: "Same Author",
        location: "22-23",
        quoteText: "Same quote"
    )

    assertNotEqual(linkedKey, manualKey, "Linked and manual quotes should not share a dedupe key namespace")
}

func testImportSkipsHighlightsWithoutBookMappings() {
    let fileURL = writeTemporaryFile(named: "verify_t73_import.txt", contents: "contents")
    let manualHighlight = Highlight(
        id: UUID(),
        bookId: nil,
        quoteText: "Manual quote",
        bookTitle: "",
        author: "",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil
    )

    var insertAttempts = 0
    var totalCountCalls = 0

    let coordinator = ImportCoordinator(
        parseClippings: { _ in
            ClippingsParser.ParseResult(
                highlights: [manualHighlight],
                books: [],
                parseErrorCount: 0,
                skippedEntryCount: 0,
                error: nil
            )
        },
        upsertBook: { book in
            book.id
        },
        insertHighlightIfNew: { _ in
            insertAttempts += 1
        },
        totalHighlightCount: {
            totalCountCalls += 1
            return 4
        }
    )

    let result = coordinator.importFile(at: fileURL)

    assertEqual(insertAttempts, 0, "Import should not attempt to persist highlights without a book mapping")
    assertEqual(result.newHighlightCount, 0, "Skipped highlights should not change the imported count")
    assertEqual(totalCountCalls, 2, "Import should still measure count delta around parsing")
    assertEqual(
        result.error,
        "Import completed with 1 skipped highlight(s) due to missing book mappings.",
        "Missing mapping path should surface an explicit warning"
    )
}

func writeTemporaryFile(named fileName: String, contents: String) -> URL {
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

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message)\nExpected: \(expected)\nActual:   \(actual)\n", stderr)
        exit(1)
    }
}

func assertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    guard lhs != rhs else {
        fputs("Assertion failed: \(message)\nBoth values were: \(lhs)\n", stderr)
        exit(1)
    }
}

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}
