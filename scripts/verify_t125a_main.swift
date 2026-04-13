import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t125a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
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

private func testLoadPagePayloadPassesInputsThrough() async {
    let expectedHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001251")!,
        quoteText: "Paged"
    )
    let expectedPayload = QuotesPagePayload(
        highlights: [expectedHighlight],
        totalMatchingHighlightCount: 42
    )
    let expectedFilters = QuotesListFilters(
        selectedBookTitle: "Book Paged",
        selectedAuthor: "Author Paged",
        bookStatus: .enabledBooksOnly,
        source: .manualOnly
    )

    let service = QuotesQueryService(
        fetchPagePayload: { searchText, filters, sortMode, limit, offset in
            assertEqual(searchText, "needle", "Expected page payload search text to pass through")
            assertEqual(filters, expectedFilters, "Expected page payload filters to pass through")
            assertEqual(sortMode, .alphabeticalByBook, "Expected page payload sort mode to pass through")
            assertEqual(limit, 25, "Expected page payload limit to use the requested page size")
            assertEqual(offset, 0, "Expected page payload fetch to begin at offset zero")
            return expectedPayload
        },
        fetchFilterOptions: { _, _ in
            QuotesFilterOptionsPayload(availableBookTitles: [], availableAuthors: [])
        },
        fetchHighlightsPage: { _, _, _, _, _ in [] }
    )

    let payload = await service.loadPagePayload(
        searchText: "needle",
        filters: expectedFilters,
        sortedBy: .alphabeticalByBook,
        pageSize: 25
    )

    assertEqual(payload, expectedPayload, "Expected page payload API to return the database payload unchanged")
}

private func testLoadFilterOptionsPassesInputsThrough() async {
    let expectedFilters = QuotesListFilters(
        selectedBookTitle: nil,
        selectedAuthor: "Author Needle",
        bookStatus: .disabledBooksOnly,
        source: .allQuotes
    )
    let expectedPayload = QuotesFilterOptionsPayload(
        availableBookTitles: ["Book A", "Book B"],
        availableAuthors: ["Author Needle"]
    )

    let service = QuotesQueryService(
        fetchPagePayload: { _, _, _, _, _ in
            QuotesPagePayload(highlights: [], totalMatchingHighlightCount: 0)
        },
        fetchFilterOptions: { searchText, filters in
            assertEqual(searchText, "author", "Expected filter-options search text to pass through")
            assertEqual(filters, expectedFilters, "Expected filter-options filters to pass through")
            return expectedPayload
        },
        fetchHighlightsPage: { _, _, _, _, _ in [] }
    )

    let payload = await service.loadFilterOptions(
        searchText: "author",
        filters: expectedFilters
    )

    assertEqual(payload, expectedPayload, "Expected filter-options API to return the database payload unchanged")
}

private func testLegacySnapshotStillComposesStagedPayloads() async {
    let expectedHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001252")!,
        quoteText: "Snapshot"
    )
    let service = QuotesQueryService(
        fetchPagePayload: { _, _, _, _, _ in
            QuotesPagePayload(
                highlights: [expectedHighlight],
                totalMatchingHighlightCount: 3
            )
        },
        fetchFilterOptions: { _, _ in
            QuotesFilterOptionsPayload(
                availableBookTitles: ["Book Snapshot"],
                availableAuthors: ["Author Snapshot"]
            )
        },
        fetchHighlightsPage: { _, _, _, _, _ in [] }
    )

    let snapshot = await service.loadSnapshot(
        searchText: "snapshot",
        filters: QuotesListFilters(),
        sortedBy: .mostRecentlyAdded,
        pageSize: 10
    )

    assertEqual(snapshot.highlights, [expectedHighlight], "Expected legacy snapshot API to reuse staged page payload results")
    assertEqual(snapshot.totalMatchingHighlightCount, 3, "Expected legacy snapshot API to reuse staged count results")
    assertEqual(snapshot.availableBookTitles, ["Book Snapshot"], "Expected legacy snapshot API to reuse staged book options")
    assertEqual(snapshot.availableAuthors, ["Author Snapshot"], "Expected legacy snapshot API to reuse staged author options")
}

@main
struct VerifyT125AMain {
    static func main() async {
        await testLoadPagePayloadPassesInputsThrough()
        await testLoadFilterOptionsPassesInputsThrough()
        await testLegacySnapshotStillComposesStagedPayloads()
        print("verify_t125a_main passed")
    }
}
