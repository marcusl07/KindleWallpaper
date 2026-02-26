import Combine
import Dispatch
import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t50_main failed: \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
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

private func waitForSemaphore(_ semaphore: DispatchSemaphore, timeout: TimeInterval) async -> Bool {
    await withCheckedContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            let result = semaphore.wait(timeout: .now() + timeout)
            continuation.resume(returning: result == .success)
        }
    }
}

private func withLock<T>(_ lock: NSLock, _ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
}

private func waitUntil(
    timeout: TimeInterval,
    pollEveryNanoseconds: UInt64 = 10_000_000,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: pollEveryNanoseconds)
    }
    return await condition()
}

@MainActor
private func testConcurrentSecondRequestReturnsFalse() async {
    let firstHighlight = makeHighlight(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        quoteText: "First quote"
    )
    let secondHighlight = makeHighlight(
        id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
        quoteText: "Second quote"
    )

    let highlightsLock = NSLock()
    var queuedHighlights = [firstHighlight, secondHighlight]
    let generationStarted = DispatchSemaphore(value: 0)
    let allowFirstGenerationToFinish = DispatchSemaphore(value: 0)
    var generationCount = 0

    let appState = AppState(
        currentQuotePreview: "Before",
        pickNextHighlight: {
            highlightsLock.lock()
            defer { highlightsLock.unlock() }
            guard !queuedHighlights.isEmpty else {
                return nil
            }
            return queuedHighlights.removeFirst()
        },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            generationCount += 1
            if generationCount == 1 {
                generationStarted.signal()
                _ = allowFirstGenerationToFinish.wait(timeout: .now() + 2)
            }
            return URL(fileURLWithPath: "/tmp/t50-concurrency-\(generationCount).png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )

    expect(appState.requestWallpaperRotation(), "Expected first requestWallpaperRotation call to be accepted")

    let started = await waitForSemaphore(generationStarted, timeout: 2)
    expect(started, "Expected first wallpaper generation to begin")

    expect(
        !appState.requestWallpaperRotation(),
        "Expected second concurrent requestWallpaperRotation call to be rejected"
    )

    allowFirstGenerationToFinish.signal()
    let firstCompleted = await waitUntil(timeout: 2) {
        await MainActor.run {
            appState.currentQuotePreview == firstHighlight.quoteText
        }
    }
    expect(firstCompleted, "Expected first wallpaper rotation to complete")

    expect(
        appState.requestWallpaperRotation(),
        "Expected in-progress flag to clear after first rotation completion"
    )

    let secondCompleted = await waitUntil(timeout: 2) {
        await MainActor.run {
            appState.currentQuotePreview == secondHighlight.quoteText
        }
    }
    expect(secondCompleted, "Expected next request to run after in-progress flag reset")
}

@MainActor
private func testSequentialRotationsUpdateMainStateAndGenerateDistinctOutputs() async {
    let tempDirectory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("kindlewall_t50_\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer {
        try? FileManager.default.removeItem(at: tempDirectory)
    }

    let wallpaperGenerator = WallpaperGenerator(
        fileManager: .default,
        appSupportDirectoryProvider: { tempDirectory },
        mainScreenPixelSizeProvider: { CGSize(width: 96, height: 64) },
        mainScreenScaleProvider: { 1.0 },
        backgroundImageLoader: BackgroundImageLoader(
            fileManager: .default,
            loadImage: { _ in nil },
            logger: { _ in }
        ),
        retainedGeneratedFileCount: 10
    )

    let highlights = [
        makeHighlight(
            id: UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!,
            quoteText: "Quote one"
        ),
        makeHighlight(
            id: UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!,
            quoteText: "Quote two"
        ),
        makeHighlight(
            id: UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!,
            quoteText: "Quote three"
        )
    ]
    let dates = [
        Date(timeIntervalSince1970: 1_736_000_001),
        Date(timeIntervalSince1970: 1_736_000_002),
        Date(timeIntervalSince1970: 1_736_000_003)
    ]

    var highlightIndex = 0
    var dateIndex = 0

    let appliedURLsLock = NSLock()
    var appliedURLs: [URL] = []
    let deliveryFlagsLock = NSLock()
    var deliveryMainQueueFlags: [Bool] = []
    let mainQueueKey = DispatchSpecificKey<String>()
    DispatchQueue.main.setSpecific(key: mainQueueKey, value: "main")

    var previewEvents: [String] = []
    var dateEvents: [Date] = []

    let appState = AppState(
        currentQuotePreview: "Before",
        pickNextHighlight: {
            guard highlightIndex < highlights.count else {
                return nil
            }
            defer { highlightIndex += 1 }
            return highlights[highlightIndex]
        },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { highlight, backgroundURL in
            wallpaperGenerator.generateWallpaper(highlight: highlight, backgroundURL: backgroundURL)
        },
        setWallpaper: { url in
            withLock(appliedURLsLock) {
                appliedURLs.append(url)
            }
        },
        markHighlightShown: { _ in },
        deliverRotationResult: { publish in
            DispatchQueue.main.async {
                withLock(deliveryFlagsLock) {
                    deliveryMainQueueFlags.append(
                        DispatchQueue.getSpecific(key: mainQueueKey) == "main"
                    )
                }
                publish()
            }
        },
        now: {
            guard dateIndex < dates.count else {
                return dates.last ?? Date()
            }
            defer { dateIndex += 1 }
            return dates[dateIndex]
        }
    )

    var cancellables = Set<AnyCancellable>()
    appState.$currentQuotePreview
        .dropFirst()
        .sink { quote in
            previewEvents.append(quote)
        }
        .store(in: &cancellables)

    appState.$lastChangedAt
        .dropFirst()
        .sink { changedAt in
            guard let changedAt else {
                return
            }
            dateEvents.append(changedAt)
        }
        .store(in: &cancellables)

    for index in 0..<highlights.count {
        expect(
            appState.requestWallpaperRotation(),
            "Expected requestWallpaperRotation call \(index + 1) to be accepted after prior completion"
        )

        let completed = await waitUntil(timeout: 3) {
            await MainActor.run {
                let appliedCount = withLock(appliedURLsLock) {
                    appliedURLs.count
                }

                return appliedCount == index + 1
                    && appState.currentQuotePreview == highlights[index].quoteText
                    && appState.lastChangedAt == dates[index]
            }
        }
        expect(completed, "Expected rotation \(index + 1) to publish quote preview and timestamp")
    }

    let capturedURLs = withLock(appliedURLsLock) {
        appliedURLs
    }
    let capturedDeliveryFlags = withLock(deliveryFlagsLock) {
        deliveryMainQueueFlags
    }

    expect(capturedURLs.count == 3, "Expected wallpaper apply to run for each of three sequential rotations")
    let uniquePaths = Set(capturedURLs.map(\.path))
    expect(uniquePaths.count == 3, "Expected each sequential rotation to produce a distinct wallpaper output path")
    expect(previewEvents == highlights.map(\.quoteText), "Expected quote preview updates for each rotation in order")
    expect(dateEvents == dates, "Expected lastChangedAt updates for each rotation in order")
    expect(capturedDeliveryFlags.count == 3, "Expected main-queue publish delivery for each rotation")
    expect(capturedDeliveryFlags.allSatisfy { $0 }, "Expected each rotation publish to run on main queue")
}

Task { @MainActor in
    await testConcurrentSecondRequestReturnsFalse()
    await testSequentialRotationsUpdateMainStateAndGenerateDistinctOutputs()
    print("verify_t50_main passed")
    exit(0)
}

dispatchMain()
