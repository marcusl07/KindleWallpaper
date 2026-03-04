import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t82_main failed: \(message)\n", stderr)
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

private func makeHighlight(
    id: UUID,
    quoteText: String
) -> Highlight {
    Highlight(
        id: id,
        bookId: UUID(uuidString: "00000000-0000-0000-0000-00000000ABCD"),
        quoteText: quoteText,
        bookTitle: "Book",
        author: "Author",
        location: "Loc 12",
        dateAdded: Date(timeIntervalSince1970: 50),
        lastShownAt: nil,
        isEnabled: true
    )
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T82-\(UUID().uuidString)"
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
private func testForcedHighlightRequestUsesProvidedHighlightInsteadOfPicker() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let forcedHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!,
        quoteText: "Forced quote"
    )
    let pickedHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!,
        quoteText: "Picked quote"
    )

    var pickCount = 0
    var generatedQuoteText: String?
    var markedIDs: [UUID] = []
    let expectedChangedAt = Date(timeIntervalSince1970: 500)

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: {
            pickCount += 1
            return pickedHighlight
        },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { highlight, _ in
            generatedQuoteText = highlight.quoteText
            return URL(fileURLWithPath: "/tmp/forced.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { markedIDs.append($0) },
        executeRotationWork: { work in work() },
        deliverRotationResult: { work in work() },
        now: { expectedChangedAt }
    )

    let didStart = appState.requestWallpaperRotation(forcedHighlight: forcedHighlight)

    assertTrue(didStart, "Expected forced wallpaper request to start")
    assertEqual(pickCount, 0, "Expected forced wallpaper request to bypass pickNextHighlight")
    assertEqual(generatedQuoteText, forcedHighlight.quoteText, "Expected wallpaper generation to use the forced highlight")
    assertEqual(markedIDs, [forcedHighlight.id], "Expected forced highlight to be marked as shown")
    assertEqual(appState.currentQuotePreview, forcedHighlight.quoteText, "Expected current quote preview to reflect the forced highlight")
    assertEqual(appState.lastChangedAt, expectedChangedAt, "Expected forced request to publish the provided timestamp")
}

@MainActor
private func testDefaultRequestStillUsesRotationPicker() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let pickedHighlight = makeHighlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000201")!,
        quoteText: "Picked by pool"
    )

    var pickCount = 0
    var generatedQuoteText: String?

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: {
            pickCount += 1
            return pickedHighlight
        },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { highlight, _ in
            generatedQuoteText = highlight.quoteText
            return URL(fileURLWithPath: "/tmp/default.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        executeRotationWork: { work in work() },
        deliverRotationResult: { work in work() }
    )

    let didStart = appState.requestWallpaperRotation()

    assertTrue(didStart, "Expected normal wallpaper request to start")
    assertEqual(pickCount, 1, "Expected normal wallpaper request to use pickNextHighlight")
    assertEqual(generatedQuoteText, pickedHighlight.quoteText, "Expected normal wallpaper request to use the picked highlight")
}

MainActor.assumeIsolated {
    testForcedHighlightRequestUsesProvidedHighlightInsteadOfPicker()
    testDefaultRequestStillUsesRotationPicker()
}

print("verify_t82_main passed")
