import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t132a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func waitUntil(
    timeoutNanoseconds: UInt64 = 1_000_000_000,
    condition: @escaping () -> Bool
) async {
    let start = DispatchTime.now().uptimeNanoseconds

    while !condition() {
        if DispatchTime.now().uptimeNanoseconds - start > timeoutNanoseconds {
            fail("Timed out waiting for asynchronous work to finish")
        }

        await Task.yield()
    }
}

private func settleTasks(iterations: Int = 20) async {
    for _ in 0..<iterations {
        await Task.yield()
    }
}

private final class LockedRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var pagePayloadSearchTexts: [String] = []
    private var filterOptionsSearchTexts: [String] = []
    private var pageSearchRequests: [(searchText: String, offset: Int)] = []

    func recordPagePayload(searchText: String) {
        lock.lock()
        pagePayloadSearchTexts.append(searchText)
        lock.unlock()
    }

    func recordFilterOptions(searchText: String) {
        lock.lock()
        filterOptionsSearchTexts.append(searchText)
        lock.unlock()
    }

    func recordPage(searchText: String, offset: Int) {
        lock.lock()
        pageSearchRequests.append((searchText, offset))
        lock.unlock()
    }

    func snapshot() -> (
        pagePayloadSearchTexts: [String],
        filterOptionsSearchTexts: [String],
        pageSearchRequests: [(searchText: String, offset: Int)]
    ) {
        lock.lock()
        let snapshot = (
            pagePayloadSearchTexts,
            filterOptionsSearchTexts,
            pageSearchRequests
        )
        lock.unlock()
        return snapshot
    }
}

@MainActor
private final class ManualDebounceSleep {
    struct Entry {
        let delay: TimeInterval
        let continuation: CheckedContinuation<Void, Never>
    }

    private(set) var entries: [Entry] = []

    func sleep(for delay: TimeInterval) async throws {
        await withCheckedContinuation { continuation in
            entries.append(Entry(delay: delay, continuation: continuation))
        }

        try Task.checkCancellation()
    }

    func resume(at index: Int) {
        entries[index].continuation.resume()
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

private func makeService(recorder: LockedRecorder) -> QuotesQueryService {
    QuotesQueryService(
        fetchPagePayload: { searchText, _, _, limit, offset in
            recorder.recordPagePayload(searchText: searchText)
            assertEqual(limit, 100, "Expected quotes refreshes to use the standard page size")
            assertEqual(offset, 0, "Expected refreshes to request the first page payload")
            return QuotesPagePayload(
                highlights: [
                    makeHighlight(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001321")!,
                        quoteText: searchText
                    )
                ],
                totalMatchingHighlightCount: 1
            )
        },
        fetchFilterOptions: { searchText, _ in
            recorder.recordFilterOptions(searchText: searchText)
            return QuotesFilterOptionsPayload(
                availableBookTitles: ["Book \(searchText)"],
                availableAuthors: ["Author \(searchText)"]
            )
        },
        fetchHighlightsPage: { searchText, _, _, limit, offset in
            recorder.recordPage(searchText: searchText, offset: offset)
            assertEqual(limit, 100, "Expected paging requests to use the standard page size")
            return [
                makeHighlight(
                    id: UUID(uuidString: "00000000-0000-0000-0000-000000001322")!,
                    quoteText: searchText
                )
            ]
        }
    )
}

@MainActor
private final class SearchDebounceHarness {
    private let scheduler: DebouncedTaskScheduler
    private let quotesQueryService: QuotesQueryService

    var searchText: String
    var effectiveSearchText: String

    private var pendingSearchRefreshTask: Task<Void, Never>?

    init(
        initialCommittedSearchText: String,
        scheduler: DebouncedTaskScheduler,
        quotesQueryService: QuotesQueryService
    ) {
        self.scheduler = scheduler
        self.quotesQueryService = quotesQueryService
        self.searchText = initialCommittedSearchText
        self.effectiveSearchText = initialCommittedSearchText
    }

    func type(_ newSearchText: String) {
        searchText = newSearchText
        pendingSearchRefreshTask = scheduler.schedule(
            after: 0.3,
            replacing: pendingSearchRefreshTask
        ) { [self] in
            pendingSearchRefreshTask = nil

            let commitState = QuotesListViewTestProbe.committedSearchRefresh(
                rawSearchText: searchText,
                effectiveSearchText: effectiveSearchText
            )
            effectiveSearchText = commitState.effectiveSearchText

            guard commitState.shouldRefresh else {
                return
            }

            guard let refreshState = QuotesListViewTestProbe.refreshQueryState(
                reason: "searchChanged",
                effectiveSearchText: effectiveSearchText,
                searchTextOverride: commitState.effectiveSearchText
            ) else {
                fail("Expected searchChanged to map to a valid refresh query state")
            }

            _ = await QuotesListViewTestProbe.simulateRefresh(
                reason: "searchChanged",
                capturedGeneration: 1,
                activeQueryGeneration: { 1 },
                preservingHighlights: [],
                totalMatchingHighlightCount: 0,
                availableBookTitles: [],
                availableAuthors: [],
                searchText: refreshState.searchText,
                filters: QuotesListFilters(),
                sortMode: .mostRecentlyAdded,
                quotesQueryService: quotesQueryService
            )
        }
    }

    func triggerRefresh(reason: String) async {
        guard let refreshState = QuotesListViewTestProbe.refreshQueryState(
            reason: reason,
            effectiveSearchText: effectiveSearchText
        ) else {
            fail("Expected \(reason) to map to a valid refresh query state")
        }

        _ = await QuotesListViewTestProbe.simulateRefresh(
            reason: reason,
            capturedGeneration: 1,
            activeQueryGeneration: { 1 },
            preservingHighlights: [],
            totalMatchingHighlightCount: 0,
            availableBookTitles: [],
            availableAuthors: [],
            searchText: refreshState.searchText,
            filters: QuotesListFilters(),
            sortMode: .mostRecentlyAdded,
            quotesQueryService: quotesQueryService
        )
    }

    func loadMore(offset: Int) async {
        let currentSearchText = QuotesListViewTestProbe.pagingSearchText(
            effectiveSearchText: effectiveSearchText
        )

        _ = await quotesQueryService.loadPage(
            searchText: currentSearchText,
            filters: QuotesListFilters(),
            sortedBy: .mostRecentlyAdded,
            limit: 100,
            offset: offset
        )
    }

    func cancel() {
        pendingSearchRefreshTask?.cancel()
        pendingSearchRefreshTask = nil
    }
}

@MainActor
private func testRapidTypingDoesNotReachQueryServiceUntilEffectiveSearchCommits() async {
    let recorder = LockedRecorder()
    let manualSleep = ManualDebounceSleep()
    let scheduler = DebouncedTaskScheduler(
        sleep: AppAsyncSleep(operation: manualSleep.sleep(for:))
    )
    let harness = SearchDebounceHarness(
        initialCommittedSearchText: "",
        scheduler: scheduler,
        quotesQueryService: makeService(recorder: recorder)
    )

    harness.type("d")
    await waitUntil {
        manualSleep.entries.count == 1
    }

    harness.type("dr")
    await waitUntil {
        manualSleep.entries.count == 2
    }

    harness.type("draft")
    await waitUntil {
        manualSleep.entries.count == 3
    }

    assertEqual(harness.effectiveSearchText, "", "Expected the effective search text to remain unchanged until the debounce resolves")

    var snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts, [], "Expected pending typing not to reach the page-payload query service")
    assertEqual(snapshot.filterOptionsSearchTexts, [], "Expected pending typing not to reach the filter-options query service")

    manualSleep.resume(at: 0)
    await settleTasks()
    snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts, [], "Expected cancelled debounce waits not to issue stale page-payload queries")
    assertEqual(snapshot.filterOptionsSearchTexts, [], "Expected cancelled debounce waits not to issue stale filter-options queries")
    assertEqual(harness.effectiveSearchText, "", "Expected cancelled debounce waits not to commit a new effective search text")

    manualSleep.resume(at: 1)
    await settleTasks()
    snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts, [], "Expected superseded debounce waits not to issue page-payload queries")
    assertEqual(snapshot.filterOptionsSearchTexts, [], "Expected superseded debounce waits not to issue filter-options queries")
    assertEqual(harness.effectiveSearchText, "", "Expected superseded debounce waits not to update the effective search text")

    manualSleep.resume(at: 2)
    await waitUntil {
        let snapshot = recorder.snapshot()
        return snapshot.pagePayloadSearchTexts.count == 1
            && snapshot.filterOptionsSearchTexts.count == 1
    }

    snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts, ["draft"], "Expected only the committed effective search term to reach page-payload queries")
    assertEqual(snapshot.filterOptionsSearchTexts, ["draft"], "Expected only the committed effective search term to reach filter-options queries")
    assertEqual(harness.effectiveSearchText, "draft", "Expected the effective search text to commit only after the debounce resolves")

    harness.cancel()
}

@MainActor
private func testRefreshesAndPagingUsePreviousCommittedSearchWhileTypingIsPending() async {
    let recorder = LockedRecorder()
    let manualSleep = ManualDebounceSleep()
    let scheduler = DebouncedTaskScheduler(
        sleep: AppAsyncSleep(operation: manualSleep.sleep(for:))
    )
    let harness = SearchDebounceHarness(
        initialCommittedSearchText: "committed",
        scheduler: scheduler,
        quotesQueryService: makeService(recorder: recorder)
    )
    let refreshReasons = [
        "sortChanged",
        "bookFilterChanged",
        "authorFilterChanged",
        "bookStatusChanged",
        "sourceFilterChanged",
        "libraryChanged"
    ]

    harness.type("draft")

    await settleTasks()
    assertEqual(manualSleep.entries.count, 1, "Expected active typing to leave one pending debounce wait")
    assertEqual(harness.effectiveSearchText, "committed", "Expected typing to preserve the previously committed search until debounce completion")

    for reason in refreshReasons {
        await harness.triggerRefresh(reason: reason)
    }
    await harness.loadMore(offset: 40)

    var snapshot = recorder.snapshot()
    assertEqual(
        snapshot.pagePayloadSearchTexts,
        Array(repeating: "committed", count: refreshReasons.count),
        "Expected non-search refreshes triggered during typing to keep querying with the previously committed search"
    )
    assertEqual(
        snapshot.filterOptionsSearchTexts,
        Array(repeating: "committed", count: refreshReasons.count - 1),
        "Expected non-sort refreshes triggered during typing to keep loading filter options with the previously committed search"
    )
    assertEqual(
        snapshot.pageSearchRequests.map(\.searchText),
        ["committed"],
        "Expected paging triggered during typing to keep using the previously committed search"
    )
    assertEqual(
        snapshot.pageSearchRequests.map(\.offset),
        [40],
        "Expected paging triggered during typing to preserve the requested offset"
    )

    manualSleep.resume(at: 0)
    await waitUntil {
        let snapshot = recorder.snapshot()
        return snapshot.pagePayloadSearchTexts.count == refreshReasons.count + 1
            && snapshot.filterOptionsSearchTexts.count == refreshReasons.count
    }

    snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts.last, "draft", "Expected the debounced search refresh to adopt the latest typed search term once committed")
    assertEqual(snapshot.filterOptionsSearchTexts.last, "draft", "Expected the debounced search refresh to load filter options for the committed search term")
    assertEqual(harness.effectiveSearchText, "draft", "Expected debounce completion to update the effective search text to the latest draft")

    harness.cancel()
}

@main
struct VerifyT132AMain {
    static func main() async {
        await testRapidTypingDoesNotReachQueryServiceUntilEffectiveSearchCommits()
        await testRefreshesAndPagingUsePreviousCommittedSearchWhileTypingIsPending()
        print("verify_t132a_main passed")
    }
}
