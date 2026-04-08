import Foundation

@main
struct VerifyT109Main {
    static func main() {
        testPersistImportPathReturnsLibrarySnapshot()
        testLegacyImportPathStillSupportsCountDelta()
        print("T109 verification passed")
    }

    private static func testPersistImportPathReturnsLibrarySnapshot() {
        let fileURL = writeTemporaryFile(named: "verify_t109_snapshot.txt")
        let parsedBookID = UUID(uuidString: "00000000-0000-0000-0000-000000001091")!
        let parsedHighlightID = UUID(uuidString: "00000000-0000-0000-0000-000000001092")!
        let expectedSnapshot = LibrarySnapshot(
            totalHighlightCount: 4,
            books: [
                Book(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000001093")!,
                    title: "Persisted Book",
                    author: "Persisted Author",
                    isEnabled: true,
                    highlightCount: 4
                )
            ]
        )

        var usedLegacyUpsert = false
        var usedLegacyInsert = false
        var usedLegacyCount = false
        var capturedBooks: [Book] = []
        var capturedHighlights: [Highlight] = []

        let coordinator = ImportCoordinator(
            parseClippings: { _ in
                ClippingsParser.ParseResult(
                    highlights: [
                        Highlight(
                            id: parsedHighlightID,
                            bookId: parsedBookID,
                            quoteText: "Snapshot quote",
                            bookTitle: "Persisted Book",
                            author: "Persisted Author",
                            location: "10-11",
                            dateAdded: nil,
                            lastShownAt: nil
                        )
                    ],
                    books: [
                        Book(
                            id: parsedBookID,
                            title: "Persisted Book",
                            author: "Persisted Author",
                            isEnabled: true,
                            highlightCount: 1
                        )
                    ],
                    parseErrorCount: 0,
                    skippedEntryCount: 0,
                    warningMessages: [],
                    error: nil
                )
            },
            upsertBook: { book in
                usedLegacyUpsert = true
                return book.id
            },
            insertHighlightIfNew: { _ in
                usedLegacyInsert = true
            },
            totalHighlightCount: {
                usedLegacyCount = true
                return 0
            },
            persistImport: { books, highlights in
                capturedBooks = books
                capturedHighlights = highlights
                return ImportPersistenceResult(
                    newHighlightCount: 1,
                    missingBookMappingCount: 0,
                    librarySnapshot: expectedSnapshot
                )
            }
        )

        let result = coordinator.importFile(at: fileURL)

        assertEqual(capturedBooks.count, 1, "Persist import path should receive parsed books")
        assertEqual(capturedHighlights.count, 1, "Persist import path should receive parsed highlights")
        assertEqual(result.newHighlightCount, 1, "Persist import path should report inserted count")
        assertEqual(result.librarySnapshot, expectedSnapshot, "Persist import path should return the database snapshot")
        assertTrue(result.error == nil, "Persist import path should remain successful when mappings are complete")
        assertTrue(!usedLegacyUpsert, "Persist import path should bypass legacy upsert calls")
        assertTrue(!usedLegacyInsert, "Persist import path should bypass legacy insert calls")
        assertTrue(!usedLegacyCount, "Persist import path should bypass legacy total-count calls")
    }

    private static func testLegacyImportPathStillSupportsCountDelta() {
        let fileURL = writeTemporaryFile(named: "verify_t109_legacy.txt")
        let parsedBookID = UUID(uuidString: "00000000-0000-0000-0000-000000001094")!
        let storedBookID = UUID(uuidString: "00000000-0000-0000-0000-000000001095")!

        var countCalls = 0

        let coordinator = ImportCoordinator(
            parseClippings: { _ in
                ClippingsParser.ParseResult(
                    highlights: [
                        Highlight(
                            id: UUID(uuidString: "00000000-0000-0000-0000-000000001096")!,
                            bookId: parsedBookID,
                            quoteText: "Legacy quote",
                            bookTitle: "Legacy Book",
                            author: "Legacy Author",
                            location: nil,
                            dateAdded: nil,
                            lastShownAt: nil
                        )
                    ],
                    books: [
                        Book(
                            id: parsedBookID,
                            title: "Legacy Book",
                            author: "Legacy Author",
                            isEnabled: true,
                            highlightCount: 1
                        )
                    ],
                    parseErrorCount: 0,
                    skippedEntryCount: 0,
                    warningMessages: [],
                    error: nil
                )
            },
            upsertBook: { _ in storedBookID },
            insertHighlightIfNew: { _ in },
            totalHighlightCount: {
                countCalls += 1
                return countCalls == 1 ? 3 : 4
            }
        )

        let result = coordinator.importFile(at: fileURL)

        assertEqual(result.newHighlightCount, 1, "Legacy import path should keep count-delta semantics")
        assertTrue(result.librarySnapshot == nil, "Legacy import path should not fabricate a snapshot")
        assertEqual(countCalls, 2, "Legacy import path should still read before and after counts")
    }

    private static func writeTemporaryFile(named fileName: String) -> URL {
        let directoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        let fileURL = directoryURL.appendingPathComponent(fileName)

        do {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            try "contents".write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            fail("Failed to prepare temporary file: \(error)")
        }
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        guard actual == expected else {
            fail("\(message). Expected \(expected), got \(actual)")
        }
    }

    private static func assertTrue(_ condition: Bool, _ message: String) {
        guard condition else {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("verify_t109_main failed: \(message)\n", stderr)
        exit(1)
    }
}
