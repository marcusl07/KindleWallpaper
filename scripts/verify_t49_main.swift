import Dispatch
import Foundation

struct BookSnapshot: Equatable {
    let id: String
    let isEnabled: Bool
    let highlightCount: Int
}

func makeBook(id: UUID, isEnabled: Bool, highlightCount: Int = 1) -> Book {
    Book(
        id: id,
        title: "Book \(id.uuidString.prefix(4))",
        author: "Author",
        isEnabled: isEnabled,
        highlightCount: highlightCount
    )
}

@MainActor
func testRapidSuccessiveMutationsStaySerialized() async {
    let bookID = UUID()
    var persistedBooks = [makeBook(id: bookID, isEnabled: false, highlightCount: 3)]
    var setBookCalls = 0
    var inFlightMutationActions = 0
    var maxInFlightMutationActions = 0
    var overlapDetected = false

    let appState = AppState(
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        setBookEnabled: { id, enabled in
            inFlightMutationActions += 1
            setBookCalls += 1
            if inFlightMutationActions > maxInFlightMutationActions {
                maxInFlightMutationActions = inFlightMutationActions
            }
            if inFlightMutationActions > 1 {
                overlapDetected = true
            }

            Thread.sleep(forTimeInterval: 0.001)

            persistedBooks = persistedBooks.map { book in
                guard book.id == id else {
                    return book
                }
                return makeBook(id: book.id, isEnabled: enabled, highlightCount: book.highlightCount)
            }

            inFlightMutationActions -= 1
        },
        fetchAllBooks: {
            persistedBooks
        },
        fetchTotalHighlightCount: {
            persistedBooks.reduce(0) { $0 + $1.highlightCount }
        }
    )

    await withTaskGroup(of: Void.self) { group in
        for index in 0..<80 {
            group.addTask { @MainActor in
                appState.setBookEnabled(id: bookID, enabled: index.isMultiple(of: 2))
            }
        }
    }

    assertTrue(setBookCalls > 20, "Expected rapid interactions to execute many persistence calls")
    assertEqual(maxInFlightMutationActions, 1, "Expected mutation actions to run serially without overlap")
    assertFalse(overlapDetected, "Expected no overlapping mutation actions")
    assertEqual(snapshot(appState.books), snapshot(persistedBooks), "Expected AppState books to match persisted state after rapid interactions")
}

@MainActor
func testInFlightFlagTransitionsDuringAndAfterMutation() async {
    var persistedBooks = [
        makeBook(id: UUID(), isEnabled: false, highlightCount: 2),
        makeBook(id: UUID(), isEnabled: false, highlightCount: 1)
    ]
    var observedInFlightInsideAction = false
    var appState: AppState!

    appState = AppState(
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        setAllBooksEnabled: { enabled in
            observedInFlightInsideAction = appState.isBookMutationInFlight
            persistedBooks = persistedBooks.map { book in
                makeBook(id: book.id, isEnabled: enabled, highlightCount: book.highlightCount)
            }
        },
        fetchAllBooks: {
            persistedBooks
        },
        fetchTotalHighlightCount: {
            persistedBooks.reduce(0) { $0 + $1.highlightCount }
        }
    )

    assertFalse(appState.isBookMutationInFlight, "Expected no in-flight mutation before bulk toggle")
    appState.setAllBooksEnabled(true)

    assertTrue(observedInFlightInsideAction, "Expected in-flight flag to be true while persistence action executes")
    assertFalse(appState.isBookMutationInFlight, "Expected in-flight flag to reset after mutation completes")
}

@MainActor
func testSequentialBulkTogglesProduceExpectedFinalState() async {
    var persistedBooks = [
        makeBook(id: UUID(), isEnabled: false, highlightCount: 5),
        makeBook(id: UUID(), isEnabled: true, highlightCount: 2),
        makeBook(id: UUID(), isEnabled: false, highlightCount: 7)
    ]
    var bulkToggleCalls: [Bool] = []

    let appState = AppState(
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        setAllBooksEnabled: { enabled in
            bulkToggleCalls.append(enabled)
            persistedBooks = persistedBooks.map { book in
                makeBook(id: book.id, isEnabled: enabled, highlightCount: book.highlightCount)
            }
        },
        fetchAllBooks: {
            persistedBooks
        },
        fetchTotalHighlightCount: {
            persistedBooks.reduce(0) { $0 + $1.highlightCount }
        }
    )

    appState.setAllBooksEnabled(true)
    appState.setAllBooksEnabled(false)
    appState.setAllBooksEnabled(true)

    assertEqual(bulkToggleCalls, [true, false, true], "Expected sequential Select All/Deselect All flow to persist each state change")
    assertTrue(appState.books.allSatisfy(\.isEnabled), "Expected final books state to reflect last bulk toggle")
}

@MainActor
func testNoOpMutationSkipsPersistenceAndRefresh() async {
    let noOpBookID = UUID()
    let initialBooks = [
        makeBook(id: noOpBookID, isEnabled: true, highlightCount: 4),
        makeBook(id: UUID(), isEnabled: true, highlightCount: 6)
    ]

    var setBookCalls = 0
    var setAllCalls = 0
    var fetchAllBooksCalls = 0
    var fetchTotalCalls = 0

    let appState = AppState(
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        setBookEnabled: { _, _ in
            setBookCalls += 1
        },
        setAllBooksEnabled: { _ in
            setAllCalls += 1
        },
        fetchAllBooks: {
            fetchAllBooksCalls += 1
            return initialBooks
        },
        fetchTotalHighlightCount: {
            fetchTotalCalls += 1
            return initialBooks.reduce(0) { $0 + $1.highlightCount }
        }
    )

    let initialFetchAllCalls = fetchAllBooksCalls
    let initialFetchTotalCalls = fetchTotalCalls

    appState.setBookEnabled(id: noOpBookID, enabled: true)
    appState.setAllBooksEnabled(true)

    assertEqual(setBookCalls, 0, "Expected per-book no-op to skip persistence action")
    assertEqual(setAllCalls, 0, "Expected bulk no-op to skip persistence action")
    assertEqual(fetchAllBooksCalls, initialFetchAllCalls, "Expected no-op mutation to skip library refresh")
    assertEqual(fetchTotalCalls, initialFetchTotalCalls, "Expected no-op mutation to skip total-count refresh")
    assertFalse(appState.isBookMutationInFlight, "Expected no lingering in-flight mutation after no-op path")
}

@MainActor
func runVerification() async {
    await testRapidSuccessiveMutationsStaySerialized()
    await testInFlightFlagTransitionsDuringAndAfterMutation()
    await testSequentialBulkTogglesProduceExpectedFinalState()
    await testNoOpMutationSkipsPersistenceAndRefresh()
}

await runVerification()
print("verify_t49_main passed")

func snapshot(_ books: [Book]) -> [BookSnapshot] {
    books
        .map {
            BookSnapshot(
                id: $0.id.uuidString.lowercased(),
                isEnabled: $0.isEnabled,
                highlightCount: $0.highlightCount
            )
        }
        .sorted { lhs, rhs in
            lhs.id < rhs.id
        }
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertFalse(_ condition: Bool, _ message: String) {
    if condition {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}
