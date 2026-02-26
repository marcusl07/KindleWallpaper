import Dispatch
import Foundation

@MainActor
func testRequestWallpaperRotationRunsOffInteractionPath() {
    let workerQueue = DispatchQueue(label: "verify.t53.worker")
    let workerQueueKey = DispatchSpecificKey<String>()
    workerQueue.setSpecific(key: workerQueueKey, value: "worker")

    let deliveryQueue = DispatchQueue(label: "verify.t53.delivery")
    let deliveryQueueKey = DispatchSpecificKey<String>()
    deliveryQueue.setSpecific(key: deliveryQueueKey, value: "delivery")

    let highlight = sampleHighlight(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        quoteText: "Keep moving."
    )
    let expectedDate = Date(timeIntervalSince1970: 1_736_100_000)

    let generationStarted = DispatchSemaphore(value: 0)
    let allowGenerationToFinish = DispatchSemaphore(value: 0)
    let rotationCompleted = DispatchSemaphore(value: 0)

    var workerQueueTag: String?
    var deliveryQueueTag: String?
    var setWallpaperCallCount = 0
    var markShownCallCount = 0

    let appState = AppState(
        currentQuotePreview: "Before",
        pickNextHighlight: { highlight },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            workerQueueTag = DispatchQueue.getSpecific(key: workerQueueKey)
            generationStarted.signal()
            _ = allowGenerationToFinish.wait(timeout: .now() + 2)
            return URL(fileURLWithPath: "/tmp/t53-generated.png")
        },
        setWallpaper: { _ in
            setWallpaperCallCount += 1
        },
        markHighlightShown: { _ in
            markShownCallCount += 1
        },
        executeRotationWork: { work in
            workerQueue.async(execute: work)
        },
        deliverRotationResult: { publish in
            deliveryQueue.async {
                deliveryQueueTag = DispatchQueue.getSpecific(key: deliveryQueueKey)
                publish()
                rotationCompleted.signal()
            }
        },
        now: { expectedDate }
    )

    let firstAccepted = appState.requestWallpaperRotation()
    assertTrue(firstAccepted, "Expected first requestWallpaperRotation call to be accepted")

    let generationDidStart = generationStarted.wait(timeout: .now() + 2) == .success
    assertTrue(generationDidStart, "Expected wallpaper generation to run on worker queue")
    assertEqual(appState.currentQuotePreview, "Before", "Expected quote preview to remain unchanged until publish stage")

    let secondAccepted = appState.requestWallpaperRotation()
    assertFalse(secondAccepted, "Expected second requestWallpaperRotation call to be rejected while first is active")

    allowGenerationToFinish.signal()
    let completed = rotationCompleted.wait(timeout: .now() + 2) == .success
    assertTrue(completed, "Expected requestWallpaperRotation completion callback to fire")

    assertEqual(workerQueueTag, "worker", "Expected wallpaper generation to execute on worker queue")
    assertEqual(deliveryQueueTag, "delivery", "Expected published state updates to run through delivery executor")
    assertEqual(setWallpaperCallCount, 1, "Expected wallpaper apply to run once")
    assertEqual(markShownCallCount, 1, "Expected highlight to be marked once")
    assertEqual(appState.currentQuotePreview, highlight.quoteText, "Expected quote preview update after publish stage")
    assertEqual(appState.lastChangedAt, expectedDate, "Expected lastChangedAt update after publish stage")
}

func sampleHighlight(id: UUID = UUID(), quoteText: String) -> Highlight {
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

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String) {
    if !condition {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

func assertFalse(_ condition: Bool, _ message: String) {
    if condition {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

Task { @MainActor in
    testRequestWallpaperRotationRunsOffInteractionPath()
    print("verify_t53_main passed")
    exit(0)
}

dispatchMain()
