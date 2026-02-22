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
assertEqual(toggleCalls.count, 1, "Expected bulk enable to toggle only currently disabled books")
assertEqual(toggleCalls[0].0, bookThreeID, "Expected bulk enable to target remaining disabled book")
assertTrue(toggleCalls[0].1, "Expected bulk enable calls to pass enabled=true")
assertTrue(appState.books.allSatisfy(\.isEnabled), "Expected all books enabled after bulk enable")

toggleCalls.removeAll()
appState.setAllBooksEnabled(true)
assertEqual(toggleCalls.count, 0, "Expected no-op bulk enable when all books already enabled")

toggleCalls.removeAll()
appState.setAllBooksEnabled(false)
assertEqual(toggleCalls.count, 3, "Expected bulk disable to toggle every enabled book")
assertTrue(toggleCalls.allSatisfy { $0.1 == false }, "Expected all bulk disable calls to pass enabled=false")
assertTrue(appState.books.allSatisfy { !$0.isEnabled }, "Expected all books disabled after bulk disable")

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
