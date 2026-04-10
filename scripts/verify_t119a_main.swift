import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t119a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fail("\(message). Expected \(expected), got \(actual)")
    }
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func testParserWarningSnippetsAreCappedAtEightyCharacters() {
    let overlongSnippet = String(repeating: "MalformedEntry", count: 12)
    let fileURL = writeTemporaryFile(
        named: "verify_t119a_parser.txt",
        contents: """
        Valid Book (Author)
        - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM

        Valid quote
        ==========
        \(overlongSnippet)
        ==========
        """
    )

    let result = ClippingsParser.parseClippings(fileURL: fileURL)
    assertEqual(result.warningMessages.count, 1, "Expected malformed trailing entry to produce one warning")

    guard let firstQuote = result.warningMessages[0].firstIndex(of: "\""),
          let lastQuote = result.warningMessages[0].lastIndex(of: "\""),
          firstQuote < lastQuote else {
        fail("Expected parser warning to include a quoted raw entry snippet")
    }

    let snippetStart = result.warningMessages[0].index(after: firstQuote)
    let snippet = String(result.warningMessages[0][snippetStart..<lastQuote])

    assertTrue(snippet.count <= 80, "Expected parser warning snippets to cap at 80 characters")
    assertTrue(snippet.hasSuffix("..."), "Expected overlong warning snippets to end in an ellipsis")
}

private func testVolumeWatcherTruncatesPersistedWarningDetailsButKeepsAccurateCount() {
    let warningMessages = (1...25).map { index in
        "Warning \(index): snippet \(index)"
    }
    let status = VolumeWatcher.makeImportStatus(
        from: VolumeWatcher.ImportPayload(
            newHighlightCount: 2,
            error: nil,
            skippedEntryCount: 0,
            warningMessages: warningMessages
        ),
        now: Date(timeIntervalSince1970: 1_713_000_000)
    )

    assertTrue(
        status.message.contains("(25 parse warnings)"),
        "Expected import summary to derive warning counts from the full warning message list"
    )
    assertEqual(status.warningDetails.count, 20, "Expected persisted warning details to cap at 20 rows")
    assertEqual(status.warningDetails[0], "Warning 1: snippet 1", "Expected persisted warning details to keep leading warnings")
    assertEqual(status.warningDetails[18], "Warning 19: snippet 19", "Expected persisted warning details to keep the nineteenth warning")
    assertEqual(status.warningDetails[19], "… and 6 more", "Expected persisted warning details to end with a truncation sentinel")
}

@MainActor
private func testAppStateImportStatusPreservesWarningDetails() {
    let appState = AppState(
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/wallpaper.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )

    let status = AppState.ImportStatus(
        message: "Last synced: Apr 10, 2026 at 9:00 AM - 1 new highlight added (2 parse warnings)",
        isError: false,
        warningDetails: [
            " First warning ",
            "",
            "Second warning"
        ]
    )

    appState.setImportStatus(status)

    assertEqual(appState.importStatus, status.message, "Expected app state to preserve the success import message")
    assertEqual(appState.importError, nil, "Expected app state success statuses to clear the error message")
    assertEqual(
        appState.importWarningDetails,
        ["First warning", "Second warning"],
        "Expected app state import status persistence to retain normalized warning details"
    )
}

private func writeTemporaryFile(named fileName: String, contents: String) -> URL {
    let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    let fileURL = directoryURL.appendingPathComponent(fileName)

    do {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        try contents.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    } catch {
        fail("Failed to write temporary file: \(error)")
    }
}

@main
struct VerifyT119AMain {
    static func main() async {
        testParserWarningSnippetsAreCappedAtEightyCharacters()
        testVolumeWatcherTruncatesPersistedWarningDetailsButKeepsAccurateCount()
        await MainActor.run {
            testAppStateImportStatusPreservesWarningDetails()
        }
        print("verify_t119a_main passed")
    }
}
