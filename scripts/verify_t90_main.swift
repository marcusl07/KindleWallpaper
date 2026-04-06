import Foundation

#if canImport(AppKit)

@main
struct VerifyT90Main {
    static func main() {
        testEmptyFileShowsImportFailure()
        testNonHighlightOnlyFileShowsImportFailure()
        testPartiallyMalformedContentShowsWarningWithCounts()

        print("T90 verification passed")
    }
}

let verificationNow = Date(timeIntervalSince1970: 1_713_000_000)

func testEmptyFileShowsImportFailure() {
    let fileURL = writeTemporaryFile(named: "verify_t90_empty.txt", contents: "")

    var totalCountCalls = 0
    let coordinator = makeCoordinator(totalCounts: [0, 0]) {
        totalCountCalls += 1
    }

    let result = coordinator.importFile(at: fileURL)
    let status = makeStatus(from: result)

    assertTrue(status.isError, "Empty clippings files should surface as an import failure")
    assertEqual(
        status.message,
        "Import failed: clippings file does not contain any valid Kindle highlight entries.",
        "Empty clippings files should not be reported as up to date"
    )
    assertEqual(totalCountCalls, 0, "Empty file failures should short-circuit before DB count checks")
}

func testNonHighlightOnlyFileShowsImportFailure() {
    let fileURL = writeTemporaryFile(
        named: "verify_t90_nonhighlight.txt",
        contents: """
        Book One (Author One)
        - Your Note on page 2 | Added on Wednesday, May 7, 2025 11:04:04 PM

        This is a note.
        ==========
        Book Two (Author Two)
        - Your Bookmark on page 7 | Added on Wednesday, May 7, 2025 11:04:04 PM

        ==========
        """
    )

    var totalCountCalls = 0
    let coordinator = makeCoordinator(totalCounts: [3, 3]) {
        totalCountCalls += 1
    }

    let result = coordinator.importFile(at: fileURL)
    let status = makeStatus(from: result)

    assertTrue(status.isError, "Files without highlight entries should surface as an import failure")
    assertEqual(
        status.message,
        "Import failed: clippings file does not contain any valid Kindle highlight entries.",
        "Ignored non-highlight entries should not collapse into Library up to date"
    )
    assertEqual(totalCountCalls, 0, "Non-highlight-only failures should short-circuit before DB count checks")
}

func testPartiallyMalformedContentShowsWarningWithCounts() {
    let fileURL = writeTemporaryFile(
        named: "verify_t90_partial.txt",
        contents: """
        Valid Book (Author)
        - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM

        Valid quote
        ==========
        Broken clipping data without Kindle metadata
        ==========
        """
    )

    let coordinator = makeCoordinator(totalCounts: [10, 11])
    let result = coordinator.importFile(at: fileURL)
    let status = makeStatus(from: result)

    assertFalse(status.isError, "Partially malformed content should remain a warning, not a failure")
    assertEqual(result.newHighlightCount, 1, "Partial malformed content should still import valid highlights")
    assertEqual(result.skippedEntryCount, 1, "Partial malformed content should report skipped entries")
    assertContains(
        status.message,
        "Import completed with warnings: 1 new highlight added, 1 entry skipped",
        "Warning should include both new-highlight and skipped-entry counts"
    )
}

func makeCoordinator(
    totalCounts: [Int],
    onTotalCount: @escaping () -> Void = {}
) -> ImportCoordinator {
    var totalCountIndex = 0

    return ImportCoordinator(
        parseClippings: ClippingsParser.parseClippings(fileURL:),
        upsertBook: { $0.id },
        insertHighlightIfNew: { _ in },
        totalHighlightCount: {
            onTotalCount()
            defer {
                totalCountIndex += 1
            }

            guard let lastCount = totalCounts.last else {
                return 0
            }

            if totalCountIndex < totalCounts.count {
                return totalCounts[totalCountIndex]
            }

            return lastCount
        }
    )
}

func makeStatus(from result: ImportResult) -> VolumeWatcher.ImportStatus {
    VolumeWatcher.makeImportStatus(
        from: VolumeWatcher.ImportPayload(
            newHighlightCount: result.newHighlightCount,
            error: result.error,
            parseWarningCount: result.parseWarningCount,
            skippedEntryCount: result.skippedEntryCount
        ),
        now: verificationNow
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
        fail("Failed to create temporary file: \(error)")
    }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message)\nExpected: \(expected)\nActual:   \(actual)\n", stderr)
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertFalse(_ condition: Bool, _ message: String) {
    assertTrue(condition == false, message)
}

func assertContains(_ string: String, _ substring: String, _ message: String) {
    guard string.contains(substring) else {
        fputs("Assertion failed: \(message)\nExpected substring: \(substring)\nActual: \(string)\n", stderr)
        exit(1)
    }
}

func fail(_ message: String) -> Never {
    fputs("\(message)\n", stderr)
    exit(1)
}

#else

@main
struct VerifyT90Main {
    static func main() {
        print("T90 verification skipped: AppKit unavailable")
    }
}

#endif
