import Foundation

let perBookID = UUID()
let bulkBookOneID = UUID()
let bulkBookTwoID = UUID()

func makeBook(id: UUID, isEnabled: Bool, highlightCount: Int = 1) -> Book {
    Book(
        id: id,
        title: "Book \(id.uuidString.prefix(4))",
        author: "Author",
        isEnabled: isEnabled,
        highlightCount: highlightCount
    )
}

func testPerBookMutationInFlightState() {
    let storeLock = NSLock()
    var persistedBooks = [makeBook(id: perBookID, isEnabled: false)]
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    let appState = AppState(
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        setBookEnabled: { id, enabled in
            entered.signal()
            _ = release.wait(timeout: .now() + 2)
            storeLock.lock()
            persistedBooks = persistedBooks.map { book in
                guard book.id == id else {
                    return book
                }
                return makeBook(id: book.id, isEnabled: enabled, highlightCount: book.highlightCount)
            }
            storeLock.unlock()
        },
        fetchAllBooks: {
            storeLock.lock()
            defer { storeLock.unlock() }
            return persistedBooks
        },
        fetchTotalHighlightCount: {
            storeLock.lock()
            defer { storeLock.unlock() }
            return persistedBooks.reduce(0) { $0 + $1.highlightCount }
        }
    )

    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        appState.setBookEnabled(id: perBookID, enabled: true)
        group.leave()
    }

    let enteredResult = entered.wait(timeout: .now() + 2)
    assertTrue(enteredResult == .success, "Expected per-book mutation action to start")
    assertTrue(appState.isBookMutationInFlight, "Expected in-flight flag to be true while per-book mutation commits")

    release.signal()
    let waitResult = group.wait(timeout: .now() + 2)
    assertTrue(waitResult == .success, "Expected per-book mutation to finish")
    assertFalse(appState.isBookMutationInFlight, "Expected in-flight flag to reset after per-book mutation")
    assertTrue(appState.books.first?.isEnabled == true, "Expected refreshed books snapshot after per-book mutation")
}

func testBulkMutationInFlightState() {
    let storeLock = NSLock()
    var persistedBooks = [
        makeBook(id: bulkBookOneID, isEnabled: true, highlightCount: 3),
        makeBook(id: bulkBookTwoID, isEnabled: false, highlightCount: 4)
    ]
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    let appState = AppState(
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        setAllBooksEnabled: { enabled in
            entered.signal()
            _ = release.wait(timeout: .now() + 2)
            storeLock.lock()
            persistedBooks = persistedBooks.map { book in
                makeBook(id: book.id, isEnabled: enabled, highlightCount: book.highlightCount)
            }
            storeLock.unlock()
        },
        fetchAllBooks: {
            storeLock.lock()
            defer { storeLock.unlock() }
            return persistedBooks
        },
        fetchTotalHighlightCount: {
            storeLock.lock()
            defer { storeLock.unlock() }
            return persistedBooks.reduce(0) { $0 + $1.highlightCount }
        }
    )

    let group = DispatchGroup()
    group.enter()
    DispatchQueue.global(qos: .userInitiated).async {
        appState.setAllBooksEnabled(false)
        group.leave()
    }

    let enteredResult = entered.wait(timeout: .now() + 2)
    assertTrue(enteredResult == .success, "Expected bulk mutation action to start")
    assertTrue(appState.isBookMutationInFlight, "Expected in-flight flag to be true while bulk mutation commits")

    release.signal()
    let waitResult = group.wait(timeout: .now() + 2)
    assertTrue(waitResult == .success, "Expected bulk mutation to finish")
    assertFalse(appState.isBookMutationInFlight, "Expected in-flight flag to reset after bulk mutation")
    assertTrue(appState.books.allSatisfy { !$0.isEnabled }, "Expected refreshed books snapshot after bulk mutation")
}

func testNoOpMutationSkipsPersistenceAndInFlight() {
    var setBookCalls = 0
    let noOpID = UUID()
    let persistedBooks = [makeBook(id: noOpID, isEnabled: true)]

    let appState = AppState(
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        setBookEnabled: { _, _ in
            setBookCalls += 1
        },
        fetchAllBooks: {
            persistedBooks
        },
        fetchTotalHighlightCount: {
            persistedBooks.reduce(0) { $0 + $1.highlightCount }
        }
    )

    assertFalse(appState.isBookMutationInFlight, "Expected no in-flight mutation before no-op action")
    appState.setBookEnabled(id: noOpID, enabled: true)
    assertEqual(setBookCalls, 0, "Expected no-op mutation to skip persistence action")
    assertFalse(appState.isBookMutationInFlight, "Expected no-op mutation to keep in-flight mutation false")
}

testPerBookMutationInFlightState()
testBulkMutationInFlightState()
testNoOpMutationSkipsPersistenceAndInFlight()

print("verify_t45_main passed")

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
