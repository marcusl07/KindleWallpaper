import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t118a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func legacyPreviewText(for quoteText: String) -> String {
    let collapsedWhitespace = quoteText.replacingOccurrences(
        of: #"\s+"#,
        with: " ",
        options: .regularExpression
    )
    let trimmed = collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? "Untitled quote" : trimmed
}

private func sleepBriefly() {
    Thread.sleep(forTimeInterval: 0.2)
}

private func makeHighlight(
    id: UUID,
    quoteText: String
) -> Highlight {
    Highlight(
        id: id,
        bookId: nil,
        quoteText: quoteText,
        bookTitle: "Book \(quoteText)",
        author: "Author \(quoteText)",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil,
        isEnabled: true
    )
}

private func loadRealHighlightPreviewCorpus() -> [String] {
    guard let rootDirectory = ProcessInfo.processInfo.environment["KINDLEWALL_ROOT_DIR"] else {
        fail("Missing KINDLEWALL_ROOT_DIR environment variable")
    }

    let sampleClippingsURL = URL(fileURLWithPath: rootDirectory)
        .appendingPathComponent("text-files/sample clippings.txt")
    let parseResult = ClippingsParser.parseClippings(fileURL: sampleClippingsURL)

    assertEqual(parseResult.error, nil, "Expected sample clippings to parse without a file-level error")
    assertTrue(
        parseResult.highlights.count >= 20,
        "Expected sample clippings corpus to provide at least 20 real highlights"
    )

    return Array(parseResult.highlights.prefix(20).map(\.quoteText))
}

private func testLoadSnapshotFetchesAllInputsInParallel() async {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000001181")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000001182")!
    let expectedHighlights = [
        makeHighlight(id: firstID, quoteText: "First"),
        makeHighlight(id: secondID, quoteText: "Second")
    ]

    let service = QuotesQueryService(
        fetchHighlightsPage: { searchText, filters, sortMode, limit, offset in
            sleepBriefly()
            assertEqual(searchText, "needle", "Expected snapshot page fetch to receive the search text")
            assertEqual(limit, 2, "Expected snapshot page fetch to receive the requested page size")
            assertEqual(offset, 0, "Expected snapshot page fetch to start from offset zero")
            return expectedHighlights
        },
        countHighlights: { searchText, filters in
            sleepBriefly()
            assertEqual(searchText, "needle", "Expected snapshot count fetch to receive the search text")
            return 7
        },
        fetchAvailableHighlightBookTitles: { searchText, filters in
            sleepBriefly()
            assertEqual(searchText, "needle", "Expected snapshot title fetch to receive the search text")
            return ["Book First", "Book Second"]
        },
        fetchAvailableHighlightAuthors: { searchText, filters in
            sleepBriefly()
            assertEqual(searchText, "needle", "Expected snapshot author fetch to receive the search text")
            return ["Author First", "Author Second"]
        }
    )

    let start = Date()
    let snapshot = await service.loadSnapshot(
        searchText: "needle",
        filters: QuotesListFilters(),
        sortedBy: .alphabeticalByBook,
        pageSize: 2
    )
    let elapsed = Date().timeIntervalSince(start)

    assertEqual(snapshot.highlights, expectedHighlights, "Expected snapshot to return the fetched page")
    assertEqual(snapshot.totalMatchingHighlightCount, 7, "Expected snapshot to return the fetched count")
    assertEqual(snapshot.availableBookTitles, ["Book First", "Book Second"], "Expected snapshot to return book title filters")
    assertEqual(snapshot.availableAuthors, ["Author First", "Author Second"], "Expected snapshot to return author filters")
    assertTrue(
        elapsed < 0.45,
        "Expected async-let snapshot fetches to complete in parallel, elapsed \(elapsed)"
    )
}

private func testLoadPagePassesPagingInputsThrough() async {
    let expectedHighlights = [
        makeHighlight(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000001183")!,
            quoteText: "Paged"
        )
    ]

    let service = QuotesQueryService(
        fetchHighlightsPage: { searchText, filters, sortMode, limit, offset in
            assertEqual(searchText, "page", "Expected page fetch to receive the search text")
            assertEqual(sortMode, .mostRecentlyAdded, "Expected page fetch to receive the sort mode")
            assertEqual(limit, 25, "Expected page fetch to receive the limit")
            assertEqual(offset, 50, "Expected page fetch to receive the offset")
            return expectedHighlights
        },
        countHighlights: { _, _ in 0 },
        fetchAvailableHighlightBookTitles: { _, _ in [] },
        fetchAvailableHighlightAuthors: { _, _ in [] }
    )

    let page = await service.loadPage(
        searchText: "page",
        filters: QuotesListFilters(),
        sortedBy: .mostRecentlyAdded,
        limit: 25,
        offset: 50
    )

    assertEqual(page, expectedHighlights, "Expected page API to return the fetch result unchanged")
}

@MainActor
private func testAppStateRetainsInjectedQuotesQueryService() {
    let service = QuotesQueryService(
        fetchHighlightsPage: { _, _, _, _, _ in [] },
        countHighlights: { _, _ in 0 },
        fetchAvailableHighlightBookTitles: { _, _ in [] },
        fetchAvailableHighlightAuthors: { _, _ in [] }
    )

    let appState = AppState(
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/wallpaper.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        quotesQueryService: service
    )

    assertTrue(appState.quotesQueryService === service, "Expected AppState to retain the injected quotes query service")
}

private func testPreviewTextMatchesLegacyNormalizationAcrossRealHighlightCorpus() {
    let realHighlights = loadRealHighlightPreviewCorpus()

    for (index, quoteText) in realHighlights.enumerated() {
        assertEqual(
            QuotesListViewTestProbe.previewText(for: quoteText),
            legacyPreviewText(for: quoteText),
            "Expected preview text normalization to stay unchanged for sample highlight \(index + 1)"
        )
    }
}

private func testPreviewTextMatchesLegacyNormalizationAcrossWhitespaceEdgeCases() {
    let edgeCases = [
        "",
        "   ",
        "\n\t  ",
        "Single line quote",
        "line one\nline two",
        "line one\r\n\r\nline two",
        "Tabs\tbetween\twords",
        "  leading and trailing  ",
        "multiple    spaces   inside",
        "mix \n of\t whitespace\r\ncharacters"
    ]

    for quoteText in edgeCases {
        assertEqual(
            QuotesListViewTestProbe.previewText(for: quoteText),
            legacyPreviewText(for: quoteText),
            "Expected preview text normalization to match the legacy regex path"
        )
    }
}

@main
struct VerifyT118AMain {
    static func main() async {
        await testLoadSnapshotFetchesAllInputsInParallel()
        await testLoadPagePassesPagingInputsThrough()
        testAppStateRetainsInjectedQuotesQueryService()
        testPreviewTextMatchesLegacyNormalizationAcrossRealHighlightCorpus()
        testPreviewTextMatchesLegacyNormalizationAcrossWhitespaceEdgeCases()
        print("verify_t118a_main passed")
    }
}
