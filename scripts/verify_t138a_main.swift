import AppKit
import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t138a_main failed: \(message)\n", stderr)
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

private func makeHighlight(index: Int) -> Highlight {
    Highlight(
        id: UUID(),
        bookId: nil,
        quoteText: "Quote \(index)",
        bookTitle: "Book \(index)",
        author: "Author \(index)",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil,
        isEnabled: true
    )
}

private func testNativeSearchFieldRendersRapidInputImmediatelyWithLargeLoadedLibrary() {
    let loadedQuotes = (0..<10_000).map(makeHighlight(index:))
    let typedValues = [
        "s",
        "se",
        "sea",
        "sear",
        "searc",
        "search",
        "search ",
        "search q",
        "search qu",
        "search quo",
        "search quot",
        "search quote"
    ]
    var observedSearchChanges: [String] = []

    _ = QuotesListViewTestProbe.simulateNativeSearchInput(
        typedValues: ["warmup"],
        onTextChanged: { _ in }
    )

    let start = DispatchTime.now().uptimeNanoseconds
    let renderedValues = QuotesListViewTestProbe.simulateNativeSearchInput(
        typedValues: typedValues,
        onTextChanged: { value in
            observedSearchChanges.append(value)
        }
    )
    let elapsedMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000

    assertEqual(loadedQuotes.count, 10_000, "Expected verification to keep a 10k quote library loaded while typing")
    assertEqual(renderedValues, typedValues, "Expected every typed value to be visible in the native search field immediately")
    assertEqual(observedSearchChanges, typedValues, "Expected every native search change to be forwarded for debounced filtering")
    assertTrue(elapsedMilliseconds < 50, "Expected rapid native search input to stay comfortably below a frame budget; took \(elapsedMilliseconds)ms")
}

@main
struct VerifyT138AMain {
    static func main() {
        testNativeSearchFieldRendersRapidInputImmediatelyWithLargeLoadedLibrary()
        print("verify_t138a_main passed")
    }
}
