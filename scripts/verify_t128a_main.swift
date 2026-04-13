import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t128a_main failed: \(message)\n", stderr)
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

private final class LockedGenerationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Int

    init(_ value: Int) {
        self.value = value
    }

    func load() -> Int {
        lock.lock()
        let snapshot = value
        lock.unlock()
        return snapshot
    }

    func store(_ newValue: Int) {
        lock.lock()
        value = newValue
        lock.unlock()
    }
}

private final class LockedRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var pagePayloadSearchTexts: [String] = []
    private(set) var filterOptionsSearchTexts: [String] = []

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

    func snapshot() -> (pagePayloadSearchTexts: [String], filterOptionsSearchTexts: [String]) {
        lock.lock()
        let snapshot = (pagePayloadSearchTexts, filterOptionsSearchTexts)
        lock.unlock()
        return snapshot
    }
}

private final class ManualQueryGate: @unchecked Sendable {
    private let startedSemaphore = DispatchSemaphore(value: 0)
    private let releaseSemaphore = DispatchSemaphore(value: 0)

    func waitForRelease() {
        startedSemaphore.signal()
        releaseSemaphore.wait()
    }

    func waitUntilStarted(timeoutSeconds: TimeInterval = 1) {
        let deadline = DispatchTime.now() + timeoutSeconds
        if startedSemaphore.wait(timeout: deadline) != .success {
            fail("Timed out waiting for gated query work to start")
        }
    }

    func release() {
        releaseSemaphore.signal()
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

private func makeRefreshService(
    recorder: LockedRecorder,
    pagePayload: @escaping @Sendable (_ searchText: String) -> QuotesPagePayload,
    filterOptions: @escaping @Sendable (_ searchText: String) -> QuotesFilterOptionsPayload
) -> QuotesQueryService {
    QuotesQueryService(
        fetchPagePayload: { searchText, _, _, limit, offset in
            recorder.recordPagePayload(searchText: searchText)
            assertEqual(limit, 100, "Expected refreshes to request the standard quotes page size")
            assertEqual(offset, 0, "Expected refreshes to request the first page payload")
            return pagePayload(searchText)
        },
        fetchFilterOptions: { searchText, _ in
            recorder.recordFilterOptions(searchText: searchText)
            return filterOptions(searchText)
        },
        fetchHighlightsPage: { _, _, _, _, _ in
            []
        }
    )
}

private func testStalePagePayloadCannotOverwriteNewerRowsOrFilterOptions() async {
    let recorder = LockedRecorder()
    let service = makeRefreshService(
        recorder: recorder,
        pagePayload: { _ in
            QuotesPagePayload(
                highlights: [
                    makeHighlight(
                        id: UUID(uuidString: "00000000-0000-0000-0000-000000001281")!,
                        quoteText: "Stale"
                    )
                ],
                totalMatchingHighlightCount: 1
            )
        },
        filterOptions: { _ in
            QuotesFilterOptionsPayload(
                availableBookTitles: ["Book Stale"],
                availableAuthors: ["Author Stale"]
            )
        }
    )

    let preservedHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001282")!,
        quoteText: "Newest"
    )
    let activeGeneration = LockedGenerationBox(9)

    let result = await QuotesListViewTestProbe.simulateRefresh(
        reason: "searchChanged",
        capturedGeneration: 8,
        activeQueryGeneration: { activeGeneration.load() },
        preservingHighlights: [preservedHighlight],
        totalMatchingHighlightCount: 3,
        availableBookTitles: ["Book Newest"],
        availableAuthors: ["Author Newest"],
        searchText: "stale",
        filters: QuotesListFilters(),
        sortMode: .mostRecentlyAdded,
        quotesQueryService: service
    )

    assertEqual(result.highlights.map(\.id), [preservedHighlight.id], "Expected stale page payloads to leave newer rows untouched")
    assertEqual(result.totalMatchingHighlightCount, 3, "Expected stale page payloads to leave newer totals untouched")
    assertEqual(result.availableBookTitles, ["Book Newest"], "Expected stale page payloads to preserve newer book filter options")
    assertEqual(result.availableAuthors, ["Author Newest"], "Expected stale page payloads to preserve newer author filter options")
    assertTrue(!result.didAcceptPagePayload, "Expected stale page payloads to be rejected")
    assertTrue(!result.didRequestFilterOptions, "Expected stale page payloads to stop before loading filter options")

    let snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts, ["stale"], "Expected the stale refresh to issue one page payload query")
    assertEqual(snapshot.filterOptionsSearchTexts, [], "Expected a rejected stale page payload to skip filter option queries")
}

private func testStaleFilterOptionsCannotOverwriteNewerOptions() async {
    let recorder = LockedRecorder()
    let filterGate = ManualQueryGate()
    let acceptedHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001283")!,
        quoteText: "Accepted"
    )
    let service = makeRefreshService(
        recorder: recorder,
        pagePayload: { _ in
            QuotesPagePayload(
                highlights: [acceptedHighlight],
                totalMatchingHighlightCount: 1
            )
        },
        filterOptions: { _ in
            filterGate.waitForRelease()
            return QuotesFilterOptionsPayload(
                availableBookTitles: ["Book Accepted"],
                availableAuthors: ["Author Accepted"]
            )
        }
    )

    let activeGeneration = LockedGenerationBox(5)
    let task = Task {
        await QuotesListViewTestProbe.simulateRefresh(
            reason: "searchChanged",
            capturedGeneration: 5,
            activeQueryGeneration: { activeGeneration.load() },
            preservingHighlights: [],
            totalMatchingHighlightCount: 0,
            availableBookTitles: ["Book Newer"],
            availableAuthors: ["Author Newer"],
            searchText: "accepted",
            filters: QuotesListFilters(),
            sortMode: .mostRecentlyAdded,
            quotesQueryService: service
        )
    }

    filterGate.waitUntilStarted()
    activeGeneration.store(6)
    filterGate.release()

    let result = await task.value

    assertEqual(result.highlights.map(\.id), [acceptedHighlight.id], "Expected the accepted page payload to stay applied")
    assertEqual(result.availableBookTitles, ["Book Newer"], "Expected stale filter options to preserve newer book options")
    assertEqual(result.availableAuthors, ["Author Newer"], "Expected stale filter options to preserve newer author options")
    assertTrue(result.didAcceptPagePayload, "Expected the page payload to be accepted before generation advanced")
    assertTrue(result.didRequestFilterOptions, "Expected search refreshes to request filter options")
    assertTrue(!result.didAcceptFilterOptions, "Expected stale filter options to be rejected")

    let snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts, ["accepted"], "Expected one accepted page payload query")
    assertEqual(snapshot.filterOptionsSearchTexts, ["accepted"], "Expected one filter-options query before the generation advanced")
}

private func testSortChangedRefreshLoadsOnlyPagePayload() async {
    let recorder = LockedRecorder()
    let highlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001284")!,
        quoteText: "Sorted"
    )
    let service = makeRefreshService(
        recorder: recorder,
        pagePayload: { _ in
            QuotesPagePayload(
                highlights: [highlight],
                totalMatchingHighlightCount: 1
            )
        },
        filterOptions: { _ in
            QuotesFilterOptionsPayload(
                availableBookTitles: ["Book Sorted"],
                availableAuthors: ["Author Sorted"]
            )
        }
    )

    let result = await QuotesListViewTestProbe.simulateRefresh(
        reason: "sortChanged",
        capturedGeneration: 4,
        activeQueryGeneration: { 4 },
        preservingHighlights: [],
        totalMatchingHighlightCount: 0,
        availableBookTitles: ["Existing Book"],
        availableAuthors: ["Existing Author"],
        searchText: "sorted",
        filters: QuotesListFilters(),
        sortMode: .alphabeticalByBook,
        quotesQueryService: service
    )

    assertEqual(result.highlights.map { $0.id }, [highlight.id], "Expected sort-only refreshes to accept the page payload")
    assertEqual(result.availableBookTitles, ["Existing Book"], "Expected sort-only refreshes to keep existing book options")
    assertEqual(result.availableAuthors, ["Existing Author"], "Expected sort-only refreshes to keep existing author options")
    assertTrue(result.didAcceptPagePayload, "Expected sort-only refreshes to accept the page payload")
    assertTrue(!result.didRequestFilterOptions, "Expected sort-only refreshes to skip filter-option loading")

    let snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts, ["sorted"], "Expected sort-only refreshes to request one page payload")
    assertEqual(snapshot.filterOptionsSearchTexts, [], "Expected sort-only refreshes to issue zero filter-options queries")
}

@MainActor
private func testDebouncedSearchRefreshProducesOneFinalEffectiveRefresh() async {
    let manualSleep = ManualDebounceSleep()
    let scheduler = DebouncedTaskScheduler(
        sleep: AppAsyncSleep(operation: manualSleep.sleep(for:))
    )
    let recorder = LockedRecorder()
    let service = makeRefreshService(
        recorder: recorder,
        pagePayload: { searchText in
            let highlight = makeHighlight(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000001285")!,
                quoteText: searchText.uppercased()
            )
            return QuotesPagePayload(
                highlights: [highlight],
                totalMatchingHighlightCount: 1
            )
        },
        filterOptions: { searchText in
            let normalized = searchText.uppercased()
            return QuotesFilterOptionsPayload(
                availableBookTitles: ["Book \(normalized)"],
                availableAuthors: ["Author \(normalized)"]
            )
        }
    )

    var searchText = ""
    let activeGeneration = LockedGenerationBox(0)
    var latestResult = QuotesListViewTestProbe.SimulatedRefreshResult(
        highlights: [],
        totalMatchingHighlightCount: 0,
        availableBookTitles: [],
        availableAuthors: [],
        didAcceptPagePayload: false,
        didRequestFilterOptions: false,
        didAcceptFilterOptions: false
    )
    var pendingTask: Task<Void, Never>? = nil

    let scheduleRefresh: @MainActor () -> Void = {
        pendingTask = scheduler.schedule(
            after: 0.3,
            replacing: pendingTask
        ) {
            let capturedGeneration = activeGeneration.load() + 1
            activeGeneration.store(capturedGeneration)
            latestResult = await QuotesListViewTestProbe.simulateRefresh(
                reason: "searchChanged",
                capturedGeneration: capturedGeneration,
                activeQueryGeneration: { activeGeneration.load() },
                preservingHighlights: latestResult.highlights,
                totalMatchingHighlightCount: latestResult.totalMatchingHighlightCount,
                availableBookTitles: latestResult.availableBookTitles,
                availableAuthors: latestResult.availableAuthors,
                searchText: searchText,
                filters: QuotesListFilters(),
                sortMode: .mostRecentlyAdded,
                quotesQueryService: service
            )
        }
    }

    searchText = "fi"
    scheduleRefresh()
    searchText = "fina"
    scheduleRefresh()
    searchText = "final"
    scheduleRefresh()

    await settleTasks()
    assertEqual(manualSleep.entries.count, 3, "Expected rapid typing to queue one debounce wait per change")
    assertEqual(manualSleep.entries.map(\.delay), [0.3, 0.3, 0.3], "Expected search debounce waits to use the production interval")

    manualSleep.resume(at: 0)
    await settleTasks()
    manualSleep.resume(at: 1)
    await settleTasks()
    manualSleep.resume(at: 2)
    await waitUntil {
        let snapshot = recorder.snapshot()
        return snapshot.pagePayloadSearchTexts.count == 1 && snapshot.filterOptionsSearchTexts.count == 1
    }
    await settleTasks()

    assertEqual(latestResult.highlights.map(\.quoteText), ["FINAL"], "Expected the final debounced refresh to resolve the last search rows")
    assertEqual(latestResult.availableBookTitles, ["Book FINAL"], "Expected the final debounced refresh to resolve the last book options")
    assertEqual(latestResult.availableAuthors, ["Author FINAL"], "Expected the final debounced refresh to resolve the last author options")
    assertTrue(latestResult.didAcceptPagePayload, "Expected the final debounced refresh to accept the page payload")
    assertTrue(latestResult.didAcceptFilterOptions, "Expected the final debounced refresh to accept filter options")
    assertEqual(activeGeneration.load(), 1, "Expected only the final debounced refresh to advance generation")

    let snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts, ["final"], "Expected rapid typing to collapse into one final effective page refresh")
    assertEqual(snapshot.filterOptionsSearchTexts, ["final"], "Expected rapid typing to collapse into one final effective filter-options refresh")

    pendingTask?.cancel()
}

@main
struct VerifyT128AMain {
    static func main() async {
        await testStalePagePayloadCannotOverwriteNewerRowsOrFilterOptions()
        await testStaleFilterOptionsCannotOverwriteNewerOptions()
        await testSortChangedRefreshLoadsOnlyPagePayload()
        await testDebouncedSearchRefreshProducesOneFinalEffectiveRefresh()
        print("verify_t128a_main passed")
    }
}
