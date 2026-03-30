import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t83_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func assertNil<T>(_ value: T?, _ message: String) {
    if value != nil {
        fail(message)
    }
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func makeBook(id: UUID, title: String, author: String) -> Book {
    Book(
        id: id,
        title: title,
        author: author,
        isEnabled: true,
        highlightCount: 3
    )
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T83-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fail("Unable to create isolated UserDefaults suite")
    }

    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "__verifySuiteName")
    return defaults
}

private func clearDefaults(_ defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: "__verifySuiteName"), !suiteName.isEmpty else {
        return
    }

    defaults.removePersistentDomain(forName: suiteName)
}

@MainActor
private func testAddManualQuoteInsertsMatchedHighlightAndRefreshesCounts() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let matchingBook = makeBook(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000701")!,
        title: "Clean Code",
        author: "Robert C. Martin"
    )

    var insertedHighlight: Highlight?
    var totalHighlightCount = 0
    let addedAt = Date(timeIntervalSince1970: 700)

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: totalHighlightCount,
        books: [matchingBook],
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        insertHighlight: { highlight in
            insertedHighlight = highlight
            totalHighlightCount += 1
        },
        fetchAllBooks: { [matchingBook] },
        fetchTotalHighlightCount: { totalHighlightCount },
        now: { addedAt }
    )

    let request = QuoteEditViewTestProbe.saveRequest(
        quoteText: "  Functions should do one thing.  ",
        bookTitle: " clean code ",
        author: " ROBERT C. MARTIN ",
        location: "  Loc 42  ",
        books: [matchingBook]
    )

    appState.addManualQuote(request)

    guard let insertedHighlight else {
        fail("Expected addManualQuote to insert a highlight")
    }

    assertEqual(insertedHighlight.bookId, matchingBook.id, "Expected matched book id to be stored on inserted highlight")
    assertEqual(insertedHighlight.quoteText, "Functions should do one thing.", "Expected inserted quote text to be trimmed")
    assertEqual(insertedHighlight.bookTitle, "Clean Code", "Expected matched book title canonicalization")
    assertEqual(insertedHighlight.author, "Robert C. Martin", "Expected matched author canonicalization")
    assertEqual(insertedHighlight.location, "Loc 42", "Expected inserted location to be trimmed")
    assertEqual(insertedHighlight.dateAdded, addedAt, "Expected manual quote insertion to stamp the current time")
    assertNil(insertedHighlight.lastShownAt, "Expected new manual quotes to start with no last shown timestamp")
    assertTrue(insertedHighlight.isEnabled, "Expected new manual quotes to start enabled")
    assertEqual(appState.totalHighlightCount, 1, "Expected library counts to refresh after insertion")
}

@MainActor
private func testAddManualQuoteAllowsUnlinkedQuotes() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    var insertedHighlight: Highlight?

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        insertHighlight: { insertedHighlight = $0 }
    )

    let request = QuoteEditViewTestProbe.saveRequest(
        quoteText: "  Independent quote  ",
        bookTitle: " New Book ",
        author: "",
        location: "   ",
        books: []
    )

    appState.addManualQuote(request)

    guard let insertedHighlight else {
        fail("Expected unlinked manual quote to insert")
    }

    assertNil(insertedHighlight.bookId, "Expected unmatched manual quotes to stay unlinked")
    assertEqual(insertedHighlight.bookTitle, "New Book", "Expected freeform book title to be preserved after trimming")
    assertEqual(insertedHighlight.author, "", "Expected blank author to remain blank")
    assertNil(insertedHighlight.location, "Expected blank location to save as nil")
}

MainActor.assumeIsolated {
    testAddManualQuoteInsertsMatchedHighlightAndRefreshesCounts()
    testAddManualQuoteAllowsUnlinkedQuotes()
}

print("verify_t83_main passed")
