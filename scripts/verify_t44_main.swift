import Foundation

struct BookSnapshot: Equatable {
    let id: String
    let isEnabled: Bool
    let highlightCount: Int
}

let initialBooks: [Book] = (0..<24).map { index in
    Book(
        id: UUID(),
        title: "Book \(index)",
        author: "Author \(index)",
        isEnabled: index.isMultiple(of: 2),
        highlightCount: (index % 7) + 1
    )
}

let trackingLock = NSLock()
let storeLock = NSLock()

var persistedBooks = initialBooks
var inFlightSections = 0
var maxInFlightSections = 0
var overlapLabels: [String] = []

func withStore<T>(_ body: () -> T) -> T {
    storeLock.lock()
    defer { storeLock.unlock() }
    return body()
}

func enterTrackedSection(_ label: String) {
    trackingLock.lock()
    inFlightSections += 1
    if inFlightSections > maxInFlightSections {
        maxInFlightSections = inFlightSections
    }
    if inFlightSections > 1 {
        overlapLabels.append(label)
    }
    trackingLock.unlock()

    // Increase overlap odds if serialization regresses.
    Thread.sleep(forTimeInterval: 0.0015)
}

func leaveTrackedSection() {
    trackingLock.lock()
    inFlightSections -= 1
    trackingLock.unlock()
}

func withTrackedSection<T>(_ label: String, _ body: () -> T) -> T {
    enterTrackedSection(label)
    defer { leaveTrackedSection() }
    return body()
}

func resetTracking() {
    trackingLock.lock()
    inFlightSections = 0
    maxInFlightSections = 0
    overlapLabels.removeAll()
    trackingLock.unlock()
}

let appState = AppState(
    pickNextHighlight: { nil },
    loadBackgroundImageURL: { nil },
    generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
    setWallpaper: { _ in },
    markHighlightShown: { _ in },
    setBookEnabled: { id, enabled in
        withTrackedSection("setBookEnabled") {
            withStore {
                persistedBooks = persistedBooks.map { book in
                    guard book.id == id else {
                        return book
                    }
                    return Book(
                        id: book.id,
                        title: book.title,
                        author: book.author,
                        isEnabled: enabled,
                        highlightCount: book.highlightCount
                    )
                }
            }
        }
    },
    setAllBooksEnabled: { enabled in
        withTrackedSection("setAllBooksEnabled") {
            withStore {
                persistedBooks = persistedBooks.map { book in
                    guard book.isEnabled != enabled else {
                        return book
                    }
                    return Book(
                        id: book.id,
                        title: book.title,
                        author: book.author,
                        isEnabled: enabled,
                        highlightCount: book.highlightCount
                    )
                }
            }
        }
    },
    fetchAllBooks: {
        withTrackedSection("fetchAllBooks") {
            withStore { persistedBooks }
        }
    },
    fetchTotalHighlightCount: {
        withTrackedSection("fetchTotalHighlightCount") {
            withStore { persistedBooks.reduce(0) { $0 + $1.highlightCount } }
        }
    }
)

resetTracking()

let concurrentQueue = DispatchQueue(label: "verify.t44.concurrent", attributes: .concurrent)
let group = DispatchGroup()
let ids = initialBooks.map(\.id)

for index in 0..<200 {
    group.enter()
    concurrentQueue.async {
        if index.isMultiple(of: 7) {
            appState.setAllBooksEnabled(index.isMultiple(of: 2))
        } else {
            let id = ids[index % ids.count]
            appState.setBookEnabled(id: id, enabled: index.isMultiple(of: 3))
        }
        group.leave()
    }
}

let waitResult = group.wait(timeout: .now() + 10)
assertTrue(waitResult == .success, "Expected concurrent mutation calls to finish")
assertEqual(maxInFlightSections, 1, "Expected serialized mutation/refetch sections with no overlap")
assertTrue(overlapLabels.isEmpty, "Expected no overlap labels when serialization is enforced")

let expectedBooksSnapshot = snapshot(withStore { persistedBooks })
let actualBooksSnapshot = snapshot(appState.books)
assertEqual(actualBooksSnapshot, expectedBooksSnapshot, "Expected AppState books snapshot to match persisted books after concurrent mutations")

let expectedTotal = withStore { persistedBooks.reduce(0) { $0 + $1.highlightCount } }
assertEqual(appState.totalHighlightCount, expectedTotal, "Expected total highlight count to stay in sync after concurrent mutations")

print("verify_t44_main passed")

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
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\\n", stderr)
        exit(1)
    }
}

func assertTrue(_ value: Bool, _ message: String) {
    if !value {
        fputs("Assertion failed: \(message)\\n", stderr)
        exit(1)
    }
}
