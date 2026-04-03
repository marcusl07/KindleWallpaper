import Foundation

#if canImport(AppKit)

@main
struct VerifyT85Main {
    static func main() {
        testUnreadableFileShowsImportFailure()
        testUndecodableFileShowsImportFailure()
        testCompletelyMalformedContentShowsImportFailure()
        testPartiallyMalformedContentShowsWarning()
        testValidFileWithZeroNewHighlightsStaysUpToDate()
        testValidFileWithNewHighlightsStaysSuccessful()
        testDateParseWarningsRemainNonFatal()

        print("T85 verification passed")
    }
}

let verificationNow = Date(timeIntervalSince1970: 1_713_000_000)

func testUnreadableFileShowsImportFailure() {
    let directoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)

    do {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    } catch {
        fail("Failed to create unreadable test directory: \(error)")
    }

    var totalCountCalls = 0
    let coordinator = makeCoordinator(totalCounts: [0, 0]) {
        totalCountCalls += 1
    }

    let result = coordinator.importFile(at: directoryURL)
    let status = makeStatus(from: result)

    assertTrue(status.isError, "Unreadable path should surface as an import failure")
    assertTrue(status.message.hasPrefix("Import failed:"), "Failure should use the Import failed prefix")
    assertContains(status.message, "could not read clippings file", "Unreadable path should mention the read failure")
    assertEqual(totalCountCalls, 0, "Unreadable path should short-circuit before DB count checks")
}

func testUndecodableFileShowsImportFailure() {
    let fileURL = writeTemporaryFile(named: "verify_t85_undecodable.txt", data: Data([0xFF, 0xFE, 0xFD]))

    var totalCountCalls = 0
    let coordinator = makeCoordinator(totalCounts: [0, 0]) {
        totalCountCalls += 1
    }

    let result = coordinator.importFile(at: fileURL)
    let status = makeStatus(from: result)

    assertTrue(status.isError, "Undecodable content should surface as an import failure")
    assertEqual(
        status.message,
        "Import failed: clippings file uses an unsupported text encoding. Use a UTF-8 text file and try again.",
        "Undecodable content should produce actionable failure text"
    )
    assertEqual(totalCountCalls, 0, "Undecodable content should short-circuit before DB count checks")
}

func testCompletelyMalformedContentShowsImportFailure() {
    let malformedURL = writeTemporaryFile(
        named: "verify_t85_malformed.txt",
        contents: """
        This is not a valid Kindle clipping export.
        """
    )

    var totalCountCalls = 0
    let coordinator = makeCoordinator(totalCounts: [0, 0]) {
        totalCountCalls += 1
    }

    let result = coordinator.importFile(at: malformedURL)
    let status = makeStatus(from: result)

    assertTrue(status.isError, "Structurally malformed content should be an import failure")
    assertEqual(
        status.message,
        "Import failed: clippings file does not contain any valid Kindle highlight entries.",
        "Malformed content should not be reported as up to date"
    )
    assertEqual(totalCountCalls, 0, "Malformed content failures should short-circuit before DB count checks")
}

func testPartiallyMalformedContentShowsWarning() {
    let fileURL = writeTemporaryFile(
        named: "verify_t85_partial.txt",
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

    assertTrue(status.isError == false, "Partial malformed content should remain a non-error warning")
    assertEqual(result.newHighlightCount, 1, "Partial malformed content should still import valid highlights")
    assertEqual(result.skippedEntryCount, 1, "Partial malformed content should count skipped entries")
    assertContains(status.message, "Import completed with warnings: 1 new highlight added, 1 entry skipped", "Warning should report new and skipped counts")
    assertTrue(status.message.contains("Last synced:"), "Warning path should use the shared sync/manual status formatter")
}

func testValidFileWithZeroNewHighlightsStaysUpToDate() {
    let fileURL = writeTemporaryFile(
        named: "verify_t85_uptodate.txt",
        contents: validHighlightContents(quote: "No new quote")
    )

    let coordinator = makeCoordinator(totalCounts: [5, 5])
    let result = coordinator.importFile(at: fileURL)
    let status = makeStatus(from: result)

    assertTrue(status.isError == false, "Valid zero-new import should not be an error")
    assertEqual(result.skippedEntryCount, 0, "Valid zero-new import should not report skipped entries")
    assertEqual(status.message, "Library up to date", "Valid zero-new import should keep the existing up-to-date message")
}

func testValidFileWithNewHighlightsStaysSuccessful() {
    let fileURL = writeTemporaryFile(
        named: "verify_t85_success.txt",
        contents: validHighlightContents(quote: "Fresh quote")
    )

    let coordinator = makeCoordinator(totalCounts: [2, 3])
    let result = coordinator.importFile(at: fileURL)
    let status = makeStatus(from: result)

    assertTrue(status.isError == false, "Valid import with new highlights should remain successful")
    assertEqual(result.skippedEntryCount, 0, "Valid import should not report skipped entries")
    assertContains(status.message, "1 new highlight added", "Successful import should keep the existing success wording")
    assertTrue(status.message.contains("Last synced:"), "Successful import should keep the timestamped success pattern")
}

func testDateParseWarningsRemainNonFatal() {
    let fileURL = writeTemporaryFile(
        named: "verify_t85_date_warning.txt",
        contents: """
        Warning Book (Author)
        - Your Highlight on page 1 | Location 1-2 | Added on not-a-kindle-date

        Date warning quote
        ==========
        """
    )

    let coordinator = makeCoordinator(totalCounts: [0, 1])
    let result = coordinator.importFile(at: fileURL)
    let status = makeStatus(from: result)

    assertTrue(status.isError == false, "Date parse warnings alone should not turn the import into a failure")
    assertEqual(result.parseWarningCount, 1, "Date parse warnings should still be counted")
    assertEqual(result.skippedEntryCount, 0, "Date parse warnings alone should not create skipped entries")
    assertContains(status.message, "1 new highlight added", "Date parse warning path should still import valid highlights")
    assertContains(status.message, "(1 parse warning)", "Date parse warning path should still surface parse warnings")
    assertFalse(status.message.contains("Import completed with warnings:"), "Date parse warnings alone should not use the malformed-entry warning wording")
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

func validHighlightContents(quote: String) -> String {
    """
    Valid Book (Author)
    - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM

    \(quote)
    ==========
    """
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

func writeTemporaryFile(named fileName: String, data: Data) -> URL {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathComponent(fileName)
    let directoryURL = fileURL.deletingLastPathComponent()

    do {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try data.write(to: fileURL)
        return fileURL
    } catch {
        fail("Failed to create temporary data file: \(error)")
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
    assertTrue(string.contains(substring), "\(message)\nActual: \(string)")
}

func fail(_ message: String) -> Never {
    fputs("Assertion failed: \(message)\n", stderr)
    exit(1)
}

#else

@main
struct VerifyT85RequiresAppKit {
    static func main() {
        fputs("T85 verification requires AppKit support.\n", stderr)
        exit(1)
    }
}

#endif
