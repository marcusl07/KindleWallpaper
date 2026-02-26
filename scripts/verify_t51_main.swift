import Dispatch
import Foundation

private enum WallpaperApplyTestError: Error {
    case failed
}

private func fail(_ message: String) -> Never {
    fputs("verify_t51_main failed: \(message)\n", stderr)
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

private func makeHighlight(
    id: UUID = UUID(),
    quoteText: String = "A focused quote"
) -> Highlight {
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

@MainActor
private func testEmptyPoolProducesNoActivePoolAndDidRotateFalse() {
    let appState = AppState(
        currentQuotePreview: "Existing Quote",
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/unused.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(outcome, .noActivePool, "Expected .noActivePool when no highlight is available")
    expect(!outcome.didRotate, "Expected didRotate=false for .noActivePool")
    expectEqual(appState.currentQuotePreview, "Existing Quote", "Expected quote preview to remain unchanged on no-op")
}

@MainActor
private func testApplyErrorProducesApplyFailureAndDidRotateFalse() {
    let appState = AppState(
        pickNextHighlight: { makeHighlight() },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/apply-error.png")
        },
        setWallpaper: { _ in
            throw WallpaperApplyTestError.failed
        },
        markHighlightShown: { _ in }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(
        outcome,
        .wallpaperApplyFailure(.applyError),
        "Expected .wallpaperApplyFailure(.applyError) when wallpaper apply throws"
    )
    expect(!outcome.didRotate, "Expected didRotate=false for wallpaper apply errors")
}

@MainActor
private func testTargetMismatchProducesMismatchFailureAndDidRotateFalse() {
    let appState = AppState(
        pickNextHighlight: { makeHighlight() },
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
                        pixelWidth: 1200,
                        pixelHeight: 800,
                        backingScaleFactor: 2.0
                    )
                ],
                applyGeneratedWallpapers: { _ in }
            )
        },
        generateWallpapers: { _, _, _ in
            [
                AppState.GeneratedWallpaper(
                    targetIdentifier: "display-2",
                    fileURL: URL(fileURLWithPath: "/tmp/wrong-target.png")
                )
            ]
        },
        markHighlightShown: { _ in }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(
        outcome,
        .wallpaperApplyFailure(.generatedTargetMismatch),
        "Expected .generatedTargetMismatch failure when generated outputs do not match targets"
    )
    expect(!outcome.didRotate, "Expected didRotate=false for generated target mismatch")
}

@MainActor
private func testSuccessProducesSuccessDidRotateTrueAndUpdatesPreview() {
    let highlight = makeHighlight(quoteText: "Updated quote preview")
    let appState = AppState(
        currentQuotePreview: "Before rotation",
        pickNextHighlight: { highlight },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/success.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(outcome, .success, "Expected .success for a successful rotation")
    expect(outcome.didRotate, "Expected didRotate=true for success")
    expectEqual(
        appState.currentQuotePreview,
        "Updated quote preview",
        "Expected currentQuotePreview to update to the selected quote on success"
    )
}

private func assertOutcomePublishedOnMainThread(
    label: String,
    expected: AppState.WallpaperRotationOutcome,
    runOutcome: @MainActor @escaping () -> AppState.WallpaperRotationOutcome
) async {
    let result: (AppState.WallpaperRotationOutcome, Bool) = await withCheckedContinuation { continuation in
        let workerQueue = DispatchQueue(label: "verify.t51.main-thread.\(label)")
        workerQueue.async {
            Task {
                let value = await MainActor.run { () -> (AppState.WallpaperRotationOutcome, Bool) in
                    let outcome = runOutcome()
                    return (outcome, Thread.isMainThread)
                }
                continuation.resume(returning: value)
            }
        }
    }

    expect(result.1, "Expected \(label) outcome publication to occur on main thread")
    expectEqual(result.0, expected, "Unexpected \(label) outcome in main-thread publication check")
}

private func testAllOutcomesPublishOnMainThread() async {
    await assertOutcomePublishedOnMainThread(
        label: "no-active-pool",
        expected: .noActivePool
    ) {
        let appState = AppState(
            pickNextHighlight: { nil },
            loadBackgroundImageURL: { nil },
            generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
            setWallpaper: { _ in },
            markHighlightShown: { _ in }
        )
        return appState.rotateWallpaperWithOutcome()
    }

    await assertOutcomePublishedOnMainThread(
        label: "apply-error",
        expected: .wallpaperApplyFailure(.applyError)
    ) {
        let appState = AppState(
            pickNextHighlight: { makeHighlight() },
            loadBackgroundImageURL: { nil },
            generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/apply-error-thread.png") },
            setWallpaper: { _ in throw WallpaperApplyTestError.failed },
            markHighlightShown: { _ in }
        )
        return appState.rotateWallpaperWithOutcome()
    }

    await assertOutcomePublishedOnMainThread(
        label: "generated-target-mismatch",
        expected: .wallpaperApplyFailure(.generatedTargetMismatch)
    ) {
        let appState = AppState(
            pickNextHighlight: { makeHighlight() },
            loadBackgroundImageURL: { nil },
            generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
            setWallpaper: { _ in },
            prepareWallpaperRotation: {
                AppState.WallpaperRotationPlan(
                    targets: [
                        AppState.WallpaperTarget(
                            identifier: "screen-1",
                            pixelWidth: 1000,
                            pixelHeight: 700,
                            backingScaleFactor: 2.0
                        )
                    ],
                    applyGeneratedWallpapers: { _ in }
                )
            },
            generateWallpapers: { _, _, _ in
                []
            },
            markHighlightShown: { _ in }
        )
        return appState.rotateWallpaperWithOutcome()
    }

    await assertOutcomePublishedOnMainThread(
        label: "success",
        expected: .success
    ) {
        let appState = AppState(
            pickNextHighlight: { makeHighlight(quoteText: "Thread-safe success") },
            loadBackgroundImageURL: { nil },
            generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/success-thread.png") },
            setWallpaper: { _ in },
            markHighlightShown: { _ in }
        )
        return appState.rotateWallpaperWithOutcome()
    }
}

await MainActor.run {
    testEmptyPoolProducesNoActivePoolAndDidRotateFalse()
    testApplyErrorProducesApplyFailureAndDidRotateFalse()
    testTargetMismatchProducesMismatchFailureAndDidRotateFalse()
    testSuccessProducesSuccessDidRotateTrueAndUpdatesPreview()
}

await testAllOutcomesPublishOnMainThread()

print("verify_t51_main passed")
