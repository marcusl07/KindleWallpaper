import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t126a_main failed: \(message)\n", stderr)
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

private final class LockedQueryRecorder {
    private let lock = NSLock()
    private var pagePayloadSearchTexts: [String] = []
    private var filterOptionsSearchTexts: [String] = []

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

@MainActor
private func testDebouncedSearchRefreshCollapsesRapidTypingIntoFinalQuery() async {
    let manualSleep = ManualDebounceSleep()
    let scheduler = DebouncedTaskScheduler(
        sleep: AppAsyncSleep(operation: manualSleep.sleep(for:))
    )
    let recorder = LockedQueryRecorder()
    let expectedHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000001261")!,
        quoteText: "Final"
    )
    let service = QuotesQueryService(
        fetchPagePayload: { searchText, _, _, limit, offset in
            recorder.recordPagePayload(searchText: searchText)
            assertEqual(limit, 100, "Expected the quotes refresh to request the standard page size")
            assertEqual(offset, 0, "Expected debounced search refreshes to request the first page")
            return QuotesPagePayload(
                highlights: [expectedHighlight],
                totalMatchingHighlightCount: 1
            )
        },
        fetchFilterOptions: { searchText, _ in
            recorder.recordFilterOptions(searchText: searchText)
            return QuotesFilterOptionsPayload(
                availableBookTitles: ["Book Final"],
                availableAuthors: ["Author Final"]
            )
        },
        fetchHighlightsPage: { _, _, _, _, _ in
            []
        }
    )

    var searchText = ""
    var pendingTask: Task<Void, Never>? = nil

    let scheduleRefresh: @MainActor () -> Void = {
        pendingTask = scheduler.schedule(
            after: 0.3,
            replacing: pendingTask
        ) {
            _ = await service.loadPagePayload(
                searchText: searchText,
                filters: QuotesListFilters(),
                sortedBy: .mostRecentlyAdded,
                pageSize: 100
            )
            _ = await service.loadFilterOptions(
                searchText: searchText,
                filters: QuotesListFilters()
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
    assertEqual(manualSleep.entries.count, 3, "Expected rapid typing to queue one debounce wait per keystroke burst")
    assertEqual(manualSleep.entries.map(\.delay), [0.3, 0.3, 0.3], "Expected every debounce wait to use the production debounce interval")

    manualSleep.resume(at: 0)
    await settleTasks()
    assertEqual(recorder.snapshot().pagePayloadSearchTexts, [], "Expected a cancelled debounce wait not to trigger a stale page-payload refresh")
    assertEqual(recorder.snapshot().filterOptionsSearchTexts, [], "Expected a cancelled debounce wait not to trigger stale filter-option refreshes")

    manualSleep.resume(at: 1)
    await settleTasks()
    assertEqual(recorder.snapshot().pagePayloadSearchTexts, [], "Expected superseded debounce waits not to reach the query service")
    assertEqual(recorder.snapshot().filterOptionsSearchTexts, [], "Expected superseded debounce waits not to load filter options")

    manualSleep.resume(at: 2)
    await waitUntil {
        let snapshot = recorder.snapshot()
        return snapshot.pagePayloadSearchTexts.count == 1 && snapshot.filterOptionsSearchTexts.count == 1
    }

    let snapshot = recorder.snapshot()
    assertEqual(snapshot.pagePayloadSearchTexts, ["final"], "Expected rapid typing to collapse into one final page-payload query")
    assertEqual(snapshot.filterOptionsSearchTexts, ["final"], "Expected the final debounced refresh to load filter options for the last search term")

    pendingTask?.cancel()
}

@main
struct VerifyT126AMain {
    static func main() async {
        await testDebouncedSearchRefreshCollapsesRapidTypingIntoFinalQuery()
        print("verify_t126a_main passed")
    }
}
