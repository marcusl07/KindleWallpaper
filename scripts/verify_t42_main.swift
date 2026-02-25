import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t42_main failed: \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private enum WallpaperApplyTestError: Error {
    case failed
}

private func makeHighlight(quoteText: String = "Quote A") -> Highlight {
    Highlight(
        id: UUID(),
        bookId: UUID(),
        quoteText: quoteText,
        bookTitle: "Book",
        author: "Author",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil
    )
}

private func makeIsolatedDefaults() -> UserDefaults {
    let suiteName = "verify_t42_\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fail("failed to create isolated UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}

private func verifySuccessfulRotationReturnsSuccessOutcome() {
    let defaults = makeIsolatedDefaults()
    let highlight = makeHighlight()
    let expectedDate = Date(timeIntervalSince1970: 1700000000)
    let wallpaperURL = URL(fileURLWithPath: "/tmp/success.png")

    var setWallpaperCalls = 0
    var markedHighlightID: UUID?

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { highlight },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in wallpaperURL },
        setWallpaper: { _ in
            setWallpaperCalls += 1
        },
        markHighlightShown: { id in
            markedHighlightID = id
        },
        now: { expectedDate }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expect(outcome == .success, "expected .success outcome for successful single-wallpaper rotation")
    expect(appState.rotateWallpaper(), "bool compatibility API should return true for success")
    expect(setWallpaperCalls == 2, "expected both explicit-outcome and bool-path rotations to apply wallpaper")
    expect(markedHighlightID == highlight.id, "expected highlight to be marked as shown")
    expect(appState.currentQuotePreview == highlight.quoteText, "expected quote preview to update")
    expect(appState.lastChangedAt == expectedDate, "expected lastChangedAt to update")
}

private func verifyNoActivePoolOutcomeSkipsSideEffects() {
    let defaults = makeIsolatedDefaults()

    var setWallpaperCalls = 0
    var markCalls = 0

    let appState = AppState(
        userDefaults: defaults,
        currentQuotePreview: "Existing Quote",
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/unused.png")
        },
        setWallpaper: { _ in
            setWallpaperCalls += 1
        },
        markHighlightShown: { _ in
            markCalls += 1
        }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expect(outcome == .noActivePool, "expected .noActivePool when no highlight is available")
    expect(!appState.rotateWallpaper(), "bool compatibility API should return false when no active pool exists")
    expect(setWallpaperCalls == 0, "wallpaper should not be applied with no active pool")
    expect(markCalls == 0, "highlight should not be marked with no active pool")
    expect(appState.currentQuotePreview == "Existing Quote", "quote preview should remain unchanged on no-op")
    expect(appState.lastChangedAt == nil, "lastChangedAt should remain unchanged on no-op")
}

private func verifyApplyFailureOutcomeSkipsMarkShownAndTimestamp() {
    let defaults = makeIsolatedDefaults()
    let highlight = makeHighlight()

    var markCalls = 0

    let appState = AppState(
        userDefaults: defaults,
        currentQuotePreview: "Existing Quote",
        pickNextHighlight: { highlight },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/fail.png")
        },
        setWallpaper: { _ in
            throw WallpaperApplyTestError.failed
        },
        markHighlightShown: { _ in
            markCalls += 1
        }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expect(
        outcome == .wallpaperApplyFailure(.applyError),
        "expected .wallpaperApplyFailure(.applyError) when wallpaper apply throws"
    )
    expect(!appState.rotateWallpaper(), "bool compatibility API should return false on apply failure")
    expect(markCalls == 0, "highlight should not be marked when wallpaper apply fails")
    expect(appState.currentQuotePreview == "Existing Quote", "quote preview should remain unchanged on apply failure")
    expect(appState.lastChangedAt == nil, "lastChangedAt should remain unchanged on apply failure")
}

private func verifyGeneratedTargetMismatchReturnsExplicitFailureOutcome() {
    let defaults = makeIsolatedDefaults()
    let highlight = makeHighlight()

    var applyCalls = 0
    var markCalls = 0

    let appState = AppState(
        userDefaults: defaults,
        pickNextHighlight: { highlight },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/unused.png")
        },
        setWallpaper: { _ in },
        prepareWallpaperRotation: {
            AppState.WallpaperRotationPlan(
                targets: [
                    AppState.WallpaperTarget(
                        identifier: "display-1",
                        pixelWidth: 100,
                        pixelHeight: 100,
                        backingScaleFactor: 2.0
                    )
                ],
                applyGeneratedWallpapers: { _ in
                    applyCalls += 1
                }
            )
        },
        generateWallpapers: { _, _, _ in
            []
        },
        markHighlightShown: { _ in
            markCalls += 1
        }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expect(
        outcome == .wallpaperApplyFailure(.generatedTargetMismatch),
        "expected explicit generated-target mismatch failure outcome"
    )
    expect(applyCalls == 0, "rotation plan apply should not run when generated targets mismatch")
    expect(markCalls == 0, "highlight should not be marked when generated targets mismatch")
}

verifySuccessfulRotationReturnsSuccessOutcome()
verifyNoActivePoolOutcomeSkipsSideEffects()
verifyApplyFailureOutcomeSkipsMarkShownAndTimestamp()
verifyGeneratedTargetMismatchReturnsExplicitFailureOutcome()
