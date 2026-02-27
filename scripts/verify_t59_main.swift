import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t59_main failed: \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fail("\(message). Expected \(expected), got \(actual)")
    }
}

private func makeHighlight(id: UUID = UUID(), quoteText: String) -> Highlight {
    Highlight(
        id: id,
        bookId: UUID(),
        quoteText: quoteText,
        bookTitle: "Book",
        author: "Author",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil
    )
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T59-\(UUID().uuidString)"
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
private func testDefaultToggleValueIsOffAndLeavesQuoteUnchanged() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    var generatedQuoteText: String?
    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { makeHighlight(quoteText: "lowercase quote") },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { highlight, _ in
            generatedQuoteText = highlight.quoteText
            return URL(fileURLWithPath: "/tmp/t59-default-off.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )

    expect(!appState.capitalizeHighlightText, "Expected capitalizeHighlightText to default to false")

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(outcome, .success, "Expected successful rotation with default toggle")
    expectEqual(generatedQuoteText, "lowercase quote", "Expected generated quote text to remain unchanged with toggle off")
    expectEqual(appState.currentQuotePreview, "lowercase quote", "Expected preview to remain unchanged with toggle off")
}

@MainActor
private func testEnabledToggleCapitalizesFirstLowercaseLetterForWallpaperAndPreview() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    defaults.capitalizeHighlightText = true

    var generatedQuoteText: String?
    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { makeHighlight(quoteText: "  \"hello world\"") },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { highlight, _ in
            generatedQuoteText = highlight.quoteText
            return URL(fileURLWithPath: "/tmp/t59-enabled.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )

    expect(appState.capitalizeHighlightText, "Expected capitalizeHighlightText to reflect stored enabled value")

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(outcome, .success, "Expected successful rotation with toggle enabled")
    expectEqual(generatedQuoteText, "  \"Hello world\"", "Expected generator input to capitalize first lowercase letter")
    expectEqual(appState.currentQuotePreview, "  \"Hello world\"", "Expected preview text to capitalize first lowercase letter")
}

@MainActor
private func testEnabledToggleDoesNotAlterAlreadyUppercaseLeadingLetter() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { makeHighlight(quoteText: "Already Uppercase") },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { highlight, _ in
            expectEqual(
                highlight.quoteText,
                "Already Uppercase",
                "Expected already-uppercase quote to remain unchanged"
            )
            return URL(fileURLWithPath: "/tmp/t59-uppercase.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )

    appState.setCapitalizeHighlightText(true)
    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(outcome, .success, "Expected successful rotation for already-uppercase quote")
    expectEqual(appState.currentQuotePreview, "Already Uppercase", "Expected preview to remain unchanged")
}

@MainActor
private func testToggleMutationPersistsToUserDefaults() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )

    expect(!defaults.capitalizeHighlightText, "Expected default stored capitalize setting to be false")
    appState.setCapitalizeHighlightText(true)
    expect(appState.capitalizeHighlightText, "Expected appState toggle to update after mutation")
    expect(defaults.capitalizeHighlightText, "Expected toggle mutation to persist to UserDefaults")
}

await MainActor.run {
    testDefaultToggleValueIsOffAndLeavesQuoteUnchanged()
    testEnabledToggleCapitalizesFirstLowercaseLetterForWallpaperAndPreview()
    testEnabledToggleDoesNotAlterAlreadyUppercaseLeadingLetter()
    testToggleMutationPersistsToUserDefaults()
}

print("verify_t59_main passed")
