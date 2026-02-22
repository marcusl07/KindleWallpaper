import Foundation

@main
struct VerifyT16Main {
    static func main() {
        testParsePipelineBuildsModelsAndCountsErrors()
        testParseErrorCountResetsPerPipelineCall()
        print("T16 verification passed")
    }

    private static func testParsePipelineBuildsModelsAndCountsErrors() {
        let raw = """
        The First Book (Author One)
        - Your Highlight on page 10 | Location 100-101 | Added on Wednesday, May 7, 2025 11:04:04 PM

        Quote one line
        ==========
        The First Book (Author One)
        - Your Highlight on page 10 | Location   100-101   | Added on Wednesday, May 7, 2025 11:04:04 PM

        Quote   one   line
        ==========
        The First Book (Author One)
        - Your Highlight on page 11 | Location 102-103 | Added on not-a-kindle-date

        Quote two line
        ==========
        Second Book -- Second Author -- Publisher
        - Your Highlight on page 1 | Added on Thursday, May 8, 2025 1:02:03 AM

        Second quote
        ==========
        Second Book -- Second Author -- Publisher
        - Your Highlight on page 1 | Added on Thursday, May 8, 2025 1:02:03 AM

           Second   quote
        ==========
        Third Book (Third Author)
        - Your Note on page 1 | Added on Thursday, May 8, 2025 1:02:03 AM

        This should be skipped
        ==========
        """

        let fileURL = writeTemporaryFile(named: "verify_t16_primary.txt", contents: raw)
        let result = ClippingsParser.parseClippings(fileURL: fileURL)

        assertEqual(result.books.count, 2, "Expected two unique parsed books")
        assertEqual(result.highlights.count, 3, "Expected deduped highlight count")
        assertEqual(result.parseErrorCount, 1, "Expected one date parse error from invalid date")

        guard let firstBook = result.books.first(where: { $0.title == "The First Book" && $0.author == "Author One" }) else {
            fail("Missing first parsed book")
        }

        guard let secondBook = result.books.first(where: { $0.title == "Second Book" && $0.author == "Second Author" }) else {
            fail("Missing second parsed book")
        }

        assertEqual(firstBook.highlightCount, 2, "First book should include two unique highlights")
        assertEqual(secondBook.highlightCount, 1, "Second book should include one unique highlight")

        let firstBookHighlights = result.highlights.filter { $0.bookId == firstBook.id }
        assertEqual(firstBookHighlights.count, 2, "First book ID should map to two highlights")
        assertTrue(
            firstBookHighlights.allSatisfy { $0.bookTitle == "The First Book" && $0.author == "Author One" },
            "First book highlights should retain cleaned display metadata"
        )

        guard let invalidDateHighlight = firstBookHighlights.first(where: { $0.quoteText == "Quote two line" }) else {
            fail("Missing highlight with invalid date")
        }
        assertTrue(invalidDateHighlight.dateAdded == nil, "Invalid date should produce nil dateAdded")
        assertEqual(invalidDateHighlight.location, "102-103", "Location should still parse when date fails")

        let secondBookHighlights = result.highlights.filter { $0.bookId == secondBook.id }
        assertEqual(secondBookHighlights.count, 1, "Second book ID should map to one highlight")
        assertTrue(secondBookHighlights[0].location == nil, "Missing location should remain nil")
        assertTrue(secondBookHighlights[0].dateAdded != nil, "Valid date should be parsed")
    }

    private static func testParseErrorCountResetsPerPipelineCall() {
        let invalidDateFileURL = writeTemporaryFile(
            named: "verify_t16_invalid_date.txt",
            contents: """
            Reset Check (Author)
            - Your Highlight on page 1 | Location 1-2 | Added on not-a-kindle-date

            One
            ==========
            """
        )

        let firstRun = ClippingsParser.parseClippings(fileURL: invalidDateFileURL)
        assertEqual(firstRun.parseErrorCount, 1, "First run should count one invalid date")

        let validDateFileURL = writeTemporaryFile(
            named: "verify_t16_valid_date.txt",
            contents: """
            Reset Check (Author)
            - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM

            Two
            ==========
            """
        )

        let secondRun = ClippingsParser.parseClippings(fileURL: validDateFileURL)
        assertEqual(secondRun.parseErrorCount, 0, "Second run should start from a reset parseErrorCount")
        assertEqual(secondRun.highlights.count, 1, "Valid file should still parse one highlight")
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
            fail("Failed to create temporary test file: \(error)")
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
