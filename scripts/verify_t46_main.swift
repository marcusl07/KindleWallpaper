import Foundation

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T46-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fputs("Assertion failed: unable to create isolated UserDefaults suite\n", stderr)
        exit(1)
    }

    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "__verifySuiteName")
    return defaults
}

func clearDefaults(_ defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: "__verifySuiteName"), !suiteName.isEmpty else {
        return
    }

    defaults.removePersistentDomain(forName: suiteName)
}

@MainActor
func runVerification() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let bookID = UUID()
    let highlightID = UUID()
    let expectedDate = Date(timeIntervalSince1970: 1_700_123_456)
    let highlight = Highlight(
        id: highlightID,
        bookId: bookID,
        quoteText: "Main-actor quote",
        bookTitle: "Actor Safety",
        author: "KindleWall",
        location: "Loc 1",
        dateAdded: nil,
        lastShownAt: nil
    )

    var booksSnapshot = [
        Book(id: bookID, title: "Actor Safety", author: "KindleWall", isEnabled: false, highlightCount: 1)
    ]
    var fetchAllBooksCallCount = 0
    var fetchTotalCountCallCount = 0
    var setBookEnabledCalls: [(UUID, Bool)] = []
    var setAllBooksEnabledCalls: [Bool] = []
    var threadChecks: [Bool] = []

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: {
            threadChecks.append(Thread.isMainThread)
            return highlight
        },
        loadBackgroundImageURL: {
            threadChecks.append(Thread.isMainThread)
            return nil
        },
        generateWallpaper: { _, _ in
            threadChecks.append(Thread.isMainThread)
            return URL(fileURLWithPath: "/tmp/kindlewall-t46.png")
        },
        setWallpaper: { _ in
            threadChecks.append(Thread.isMainThread)
        },
        markHighlightShown: { _ in
            threadChecks.append(Thread.isMainThread)
        },
        setBookEnabled: { id, enabled in
            threadChecks.append(Thread.isMainThread)
            setBookEnabledCalls.append((id, enabled))
            if let index = booksSnapshot.firstIndex(where: { $0.id == id }) {
                booksSnapshot[index].isEnabled = enabled
            }
        },
        setAllBooksEnabled: { enabled in
            threadChecks.append(Thread.isMainThread)
            setAllBooksEnabledCalls.append(enabled)
            for index in booksSnapshot.indices {
                booksSnapshot[index].isEnabled = enabled
            }
        },
        fetchAllBooks: {
            threadChecks.append(Thread.isMainThread)
            fetchAllBooksCallCount += 1
            return booksSnapshot
        },
        fetchTotalHighlightCount: {
            threadChecks.append(Thread.isMainThread)
            fetchTotalCountCallCount += 1
            return 1
        },
        now: {
            threadChecks.append(Thread.isMainThread)
            return expectedDate
        }
    )

    expect(fetchAllBooksCallCount >= 1, "Expected initial books fetch during AppState initialization")
    expect(fetchTotalCountCallCount >= 1, "Expected initial highlight count fetch during AppState initialization")
    expect(appState.rotateWallpaperWithOutcome() == .success, "Expected rotation success on active highlight pool")
    expect(appState.currentQuotePreview == highlight.quoteText, "Expected quote preview to update on successful rotation")
    expect(appState.lastChangedAt == expectedDate, "Expected lastChangedAt to update using injected clock")

    appState.setBookEnabled(id: bookID, enabled: true)
    expect(setBookEnabledCalls.count == 1, "Expected one per-book toggle invocation")
    expect(setBookEnabledCalls.first?.0 == bookID, "Expected per-book toggle to target requested book")
    expect(setBookEnabledCalls.first?.1 == true, "Expected per-book toggle to persist requested enabled value")

    appState.setAllBooksEnabled(false)
    expect(setAllBooksEnabledCalls == [false], "Expected one bulk toggle invocation")

    expect(threadChecks.allSatisfy { $0 }, "Expected injected AppState dependencies to run on main thread")
}

await MainActor.run {
    runVerification()
}

print("T46 runtime verification passed")
