import Foundation

@main
struct VerifyT17Main {
    static func main() {
        testImportMapsBookIDsAndImportsHighlights()
        testImportUsesDatabaseCountDeltaForNewHighlightCount()
        testImportReturnsErrorForMissingFile()
        print("T17 verification passed")
    }

    private static func testImportMapsBookIDsAndImportsHighlights() {
        let fileURL = writeTemporaryFile(named: "verify_t17_primary.txt", contents: "contents")

        let parsedBookIDOne = UUID()
        let parsedBookIDTwo = UUID()
        let storedBookIDOne = UUID()
        let storedBookIDTwo = UUID()

        let parsedBooks = [
            Book(id: parsedBookIDOne, title: "Book One", author: "Author One", isEnabled: true, highlightCount: 2),
            Book(id: parsedBookIDTwo, title: "Book Two", author: "Author Two", isEnabled: true, highlightCount: 1)
        ]

        let parsedHighlights = [
            Highlight(
                id: UUID(),
                bookId: parsedBookIDOne,
                quoteText: "Quote A",
                bookTitle: "Book One",
                author: "Author One",
                location: "10-11",
                dateAdded: nil,
                lastShownAt: nil
            ),
            Highlight(
                id: UUID(),
                bookId: parsedBookIDOne,
                quoteText: "Quote B",
                bookTitle: "Book One",
                author: "Author One",
                location: "12-13",
                dateAdded: nil,
                lastShownAt: nil
            ),
            Highlight(
                id: UUID(),
                bookId: parsedBookIDTwo,
                quoteText: "Quote C",
                bookTitle: "Book Two",
                author: "Author Two",
                location: nil,
                dateAdded: nil,
                lastShownAt: nil
            )
        ]

        var upsertedBooks: [Book] = []
        var insertedHighlights: [Highlight] = []
        var totalCountCalls = 0

        let coordinator = ImportCoordinator(
            parseClippings: { _ in
                (highlights: parsedHighlights, books: parsedBooks, parseErrorCount: 2)
            },
            upsertBook: { book in
                upsertedBooks.append(book)
                if book.id == parsedBookIDOne {
                    return storedBookIDOne
                }
                return storedBookIDTwo
            },
            insertHighlightIfNew: { highlight in
                insertedHighlights.append(highlight)
            },
            totalHighlightCount: {
                totalCountCalls += 1
                return totalCountCalls == 1 ? 5 : 8
            }
        )

        let result = coordinator.importFile(at: fileURL)

        assertEqual(result.newHighlightCount, 3, "Import should report the DB count delta")
        assertTrue(result.error == nil, "Successful import should not return an error")
        assertEqual(result.parseWarningCount, 2, "Expected parse warning count to propagate from parser output")
        assertEqual(upsertedBooks.count, 2, "Should upsert each parsed book once")
        assertEqual(insertedHighlights.count, 3, "Should attempt to insert all parsed highlights")
        assertEqual(totalCountCalls, 2, "Should read total counts before and after import")
        assertTrue(
            insertedHighlights[0].bookId == storedBookIDOne &&
            insertedHighlights[1].bookId == storedBookIDOne &&
            insertedHighlights[2].bookId == storedBookIDTwo,
            "Highlights should be remapped to persisted book IDs"
        )
    }

    private static func testImportUsesDatabaseCountDeltaForNewHighlightCount() {
        let fileURL = writeTemporaryFile(named: "verify_t17_dedupe.txt", contents: "contents")

        let parsedBookID = UUID()
        let storedBookID = UUID()
        let parsedBook = Book(id: parsedBookID, title: "Deduped Book", author: "Author", isEnabled: true, highlightCount: 3)

        let parsedHighlights = [
            Highlight(
                id: UUID(),
                bookId: parsedBookID,
                quoteText: "Duplicate quote one",
                bookTitle: "Deduped Book",
                author: "Author",
                location: "1-2",
                dateAdded: nil,
                lastShownAt: nil
            ),
            Highlight(
                id: UUID(),
                bookId: parsedBookID,
                quoteText: "Duplicate quote one",
                bookTitle: "Deduped Book",
                author: "Author",
                location: "1-2",
                dateAdded: nil,
                lastShownAt: nil
            ),
            Highlight(
                id: UUID(),
                bookId: parsedBookID,
                quoteText: "Duplicate quote one",
                bookTitle: "Deduped Book",
                author: "Author",
                location: "1-2",
                dateAdded: nil,
                lastShownAt: nil
            )
        ]

        var insertedAttempts = 0
        var totalCountCalls = 0

        let coordinator = ImportCoordinator(
            parseClippings: { _ in
                (highlights: parsedHighlights, books: [parsedBook], parseErrorCount: 1)
            },
            upsertBook: { _ in storedBookID },
            insertHighlightIfNew: { _ in
                insertedAttempts += 1
            },
            totalHighlightCount: {
                totalCountCalls += 1
                return totalCountCalls == 1 ? 11 : 12
            }
        )

        let result = coordinator.importFile(at: fileURL)

        assertEqual(insertedAttempts, 3, "Coordinator should pass all parsed highlights to the DB dedupe layer")
        assertEqual(result.newHighlightCount, 1, "New highlight count should use DB before/after totals")
        assertTrue(result.error == nil, "Count-delta based dedupe should still be a successful import")
        assertEqual(result.parseWarningCount, 1, "Expected parse warning count to propagate for deduped imports too")
    }

    private static func testImportReturnsErrorForMissingFile() {
        let missingURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("missing.txt")

        var parseCalled = false
        var upsertCalled = false
        var insertCalled = false
        var countCalled = false

        let coordinator = ImportCoordinator(
            parseClippings: { _ in
                parseCalled = true
                return (highlights: [], books: [], parseErrorCount: 0)
            },
            upsertBook: { book in
                upsertCalled = true
                return book.id
            },
            insertHighlightIfNew: { _ in
                insertCalled = true
            },
            totalHighlightCount: {
                countCalled = true
                return 0
            }
        )

        let result = coordinator.importFile(at: missingURL)

        assertEqual(result.newHighlightCount, 0, "Missing file should not report new highlights")
        assertTrue(result.error != nil, "Missing file should return an error")
        assertEqual(result.parseWarningCount, 0, "Missing file should not report parse warnings")
        assertTrue(
            parseCalled == false && upsertCalled == false && insertCalled == false && countCalled == false,
            "Missing file path should short-circuit before parsing or DB calls"
        )
    }

    private static func writeTemporaryFile(named fileName: String, contents: String) -> URL {
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

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fputs("Assertion failed: \(message)\nExpected: \(expected)\nActual:   \(actual)\n", stderr)
            exit(1)
        }
    }

    private static func assertTrue(_ condition: Bool, _ message: String) {
        guard condition else {
            fputs("Assertion failed: \(message)\n", stderr)
            exit(1)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}
