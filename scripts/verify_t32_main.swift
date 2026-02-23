import Foundation

let bookOneID = UUID(uuidString: "8DBB2B13-5D24-4668-8A95-516F076FB9F2")!
let bookTwoID = UUID(uuidString: "4982A3BC-2EEC-4AB5-B255-66FC2D7D6544")!
let bookThreeID = UUID(uuidString: "100542ED-BD2E-4EFD-A810-42B7AC9A1ABA")!

var persistedBooks = [
    Book(id: bookOneID, title: "One", author: "A", isEnabled: true, highlightCount: 3),
    Book(id: bookTwoID, title: "Two", author: "B", isEnabled: false, highlightCount: 5),
    Book(id: bookThreeID, title: "Three", author: "C", isEnabled: false, highlightCount: 2)
]

var toggleCalls: [(UUID, Bool)] = []
var bulkToggleCalls: [Bool] = []

let appState = AppState(
    pickNextHighlight: { nil },
    loadBackgroundImageURL: { nil },
    generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
    setWallpaper: { _ in },
    markHighlightShown: { _ in },
    setBookEnabled: { id, enabled in
        toggleCalls.append((id, enabled))
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
    },
    setAllBooksEnabled: { enabled in
        bulkToggleCalls.append(enabled)
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
    },
    fetchAllBooks: { persistedBooks },
    fetchTotalHighlightCount: { persistedBooks.reduce(0) { $0 + $1.highlightCount } }
)

assertEqual(appState.books.count, 3, "Expected initial books to load from fetchAllBooks")
assertFalse(appState.books[1].isEnabled, "Expected second book initially disabled")

appState.setBookEnabled(id: bookTwoID, enabled: true)
assertEqual(toggleCalls.count, 1, "Expected one per-book toggle call")
assertEqual(toggleCalls[0].0, bookTwoID, "Expected per-book toggle to pass selected book id")
assertTrue(toggleCalls[0].1, "Expected per-book toggle to pass enabled=true")
assertTrue(appState.books.first(where: { $0.id == bookTwoID })?.isEnabled == true, "Expected books snapshot refresh after per-book toggle")

toggleCalls.removeAll()
appState.setAllBooksEnabled(true)
assertEqual(toggleCalls.count, 0, "Expected bulk enable to avoid per-book toggle calls")
assertEqual(bulkToggleCalls, [true], "Expected bulk enable to call setAllBooksEnabled once")
assertTrue(appState.books.allSatisfy(\.isEnabled), "Expected all books enabled after bulk enable")

appState.setAllBooksEnabled(true)
assertEqual(bulkToggleCalls, [true], "Expected no-op bulk enable when all books already enabled")

appState.setAllBooksEnabled(false)
assertEqual(toggleCalls.count, 0, "Expected bulk disable to avoid per-book toggle calls")
assertEqual(bulkToggleCalls, [true, false], "Expected bulk disable to call setAllBooksEnabled once")
assertTrue(appState.books.allSatisfy { !$0.isEnabled }, "Expected all books disabled after bulk disable")

// High-count regression coverage: verify mixed single/bulk toggles stay consistent across many rows.
toggleCalls.removeAll()
bulkToggleCalls.removeAll()

let manyBookIDs = (0..<40).map { _ in UUID() }
persistedBooks = manyBookIDs.enumerated().map { index, id in
    Book(
        id: id,
        title: "Book \(index)",
        author: "Author \(index)",
        isEnabled: index.isMultiple(of: 2),
        highlightCount: index + 1
    )
}

let highCountState = AppState(
    pickNextHighlight: { nil },
    loadBackgroundImageURL: { nil },
    generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
    setWallpaper: { _ in },
    markHighlightShown: { _ in },
    setBookEnabled: { id, enabled in
        toggleCalls.append((id, enabled))
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
    },
    setAllBooksEnabled: { enabled in
        bulkToggleCalls.append(enabled)
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
    },
    fetchAllBooks: { persistedBooks },
    fetchTotalHighlightCount: { persistedBooks.reduce(0) { $0 + $1.highlightCount } }
)

assertEqual(highCountState.books.count, 40, "Expected high-count state to load all books")

let targetedIndexes = [0, 3, 10, 25, 39]
for index in targetedIndexes {
    let bookID = manyBookIDs[index]
    let currentValue = highCountState.books.first(where: { $0.id == bookID })!.isEnabled
    highCountState.setBookEnabled(id: bookID, enabled: !currentValue)
    let updatedValue = highCountState.books.first(where: { $0.id == bookID })!.isEnabled
    assertEqual(updatedValue, !currentValue, "Expected targeted book toggle to persist for index \(index)")
}
assertEqual(toggleCalls.count, targetedIndexes.count, "Expected one per-book mutation call per targeted toggle")

let noOpID = manyBookIDs[7]
let noOpValue = highCountState.books.first(where: { $0.id == noOpID })!.isEnabled
highCountState.setBookEnabled(id: noOpID, enabled: noOpValue)
assertEqual(toggleCalls.count, targetedIndexes.count, "Expected no-op per-book toggle to skip persistence call")

highCountState.setAllBooksEnabled(false)
assertTrue(highCountState.books.allSatisfy { !$0.isEnabled }, "Expected bulk disable to disable every book in high-count state")

highCountState.setAllBooksEnabled(true)
assertTrue(highCountState.books.allSatisfy(\.isEnabled), "Expected bulk enable to enable every book in high-count state")

for index in stride(from: 1, to: manyBookIDs.count, by: 3) {
    let bookID = manyBookIDs[index]
    highCountState.setBookEnabled(id: bookID, enabled: false)
}
let expectedDisabledCount = Array(stride(from: 1, to: manyBookIDs.count, by: 3)).count
let actualDisabledCount = highCountState.books.filter { !$0.isEnabled }.count
assertEqual(actualDisabledCount, expectedDisabledCount, "Expected deterministic disabled count after mixed single toggles")

highCountState.setAllBooksEnabled(true)
assertTrue(highCountState.books.allSatisfy(\.isEnabled), "Expected final bulk enable to recover all rows to enabled")
assertEqual(bulkToggleCalls, [false, true, true], "Expected two meaningful bulk mutations and one final recovery mutation")

print("verify_t32_main passed")

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertTrue(_ value: Bool, _ message: String) {
    if !value {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertFalse(_ value: Bool, _ message: String) {
    assertTrue(!value, message)
}
