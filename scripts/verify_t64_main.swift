import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t64_main failed: \(message)\n", stderr)
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

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T64-\(UUID().uuidString)"
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

private func makeHighlight(id: UUID = UUID(), quoteText: String = "Quote") -> Highlight {
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

private func makeTemporaryDirectory(prefix: String) -> URL {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    } catch {
        fail("Unable to create temporary directory: \(error)")
    }
    return directory
}

private func makeResolvedScreen(
    screen: String,
    identifier: String,
    pixelWidth: Int = 1,
    pixelHeight: Int = 1,
    backingScaleFactor: CGFloat = 1.0,
    originX: Int = 0,
    originY: Int = 0
) -> WallpaperSetter.ResolvedScreen<String> {
    WallpaperSetter.ResolvedScreen(
        screen: screen,
        identifier: identifier,
        pixelWidth: pixelWidth,
        pixelHeight: pixelHeight,
        backingScaleFactor: backingScaleFactor,
        originX: originX,
        originY: originY
    )
}

private func makeWallpaper(directory: URL, name: String) -> URL {
    let fileURL = directory.appendingPathComponent(name, isDirectory: false)
    FileManager.default.createFile(atPath: fileURL.path, contents: Data(name.utf8))
    return fileURL
}

private func testReplaceReusableGeneratedWallpapersReplacesStoredSnapshot() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-replace")
    defer { try? FileManager.default.removeItem(at: directory) }

    let originalURL = makeWallpaper(directory: directory, name: "display-a-original.png")
    let replacementURL = makeWallpaper(directory: directory, name: "display-a-replacement.png")
    let removedURL = makeWallpaper(directory: directory, name: "display-b.png")

    defaults.replaceReusableGeneratedWallpapers([
        StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: originalURL),
        StoredGeneratedWallpaper(targetIdentifier: "display-b", fileURL: removedURL)
    ])
    defaults.replaceReusableGeneratedWallpapers([
        StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: replacementURL)
    ])

    let storedWallpapers = defaults.loadReusableGeneratedWallpapers()
    expectEqual(storedWallpapers.count, 1, "Expected replace to drop omitted wallpaper assignments")
    expectEqual(storedWallpapers[0].targetIdentifier, "display-a", "Expected replace to keep the requested target identifier")
    expectEqual(
        storedWallpapers[0].fileURL.standardizedFileURL,
        replacementURL.standardizedFileURL,
        "Expected replace to overwrite the existing target entry"
    )
}

private func testMergeReusableGeneratedWallpapersMergesByTargetIdentifier() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-merge")
    defer { try? FileManager.default.removeItem(at: directory) }

    let originalAURL = makeWallpaper(directory: directory, name: "display-a-original.png")
    let originalBURL = makeWallpaper(directory: directory, name: "display-b-original.png")
    let replacementBURL = makeWallpaper(directory: directory, name: "display-b-replacement.png")
    let addedCURL = makeWallpaper(directory: directory, name: "display-c.png")

    defaults.replaceReusableGeneratedWallpapers([
        StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: originalAURL),
        StoredGeneratedWallpaper(targetIdentifier: "display-b", fileURL: originalBURL)
    ])
    defaults.mergeReusableGeneratedWallpapers([
        StoredGeneratedWallpaper(targetIdentifier: "display-b", fileURL: replacementBURL),
        StoredGeneratedWallpaper(targetIdentifier: "display-c", fileURL: addedCURL)
    ])

    let storedWallpapers = defaults.loadReusableGeneratedWallpapers()
    expectEqual(storedWallpapers.count, 3, "Expected merge to preserve untouched assignments and add new ones")
    expectEqual(storedWallpapers[0].targetIdentifier, "display-a", "Expected merge to preserve existing unmatched targets")
    expectEqual(storedWallpapers[0].fileURL.standardizedFileURL, originalAURL.standardizedFileURL, "Expected merge to preserve the existing target URL")
    expectEqual(storedWallpapers[1].targetIdentifier, "display-b", "Expected merge to keep the replaced target identifier")
    expectEqual(storedWallpapers[1].fileURL.standardizedFileURL, replacementBURL.standardizedFileURL, "Expected merge to overwrite matching targets")
    expectEqual(storedWallpapers[2].targetIdentifier, "display-c", "Expected merge to append newly merged targets")
    expectEqual(storedWallpapers[2].fileURL.standardizedFileURL, addedCURL.standardizedFileURL, "Expected merge to store the added target URL")
}

private func testClearReusableGeneratedWallpapersRemovesStoredAssignments() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-clear")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "display-a.png")
    defaults.replaceReusableGeneratedWallpapers([
        StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: wallpaperURL)
    ])

    defaults.clearReusableGeneratedWallpapers()

    expect(
        defaults.object(forKey: "reusableGeneratedWallpaperPathsByTarget") == nil,
        "Expected clear to remove the persisted assignments key"
    )
    expectEqual(defaults.loadReusableGeneratedWallpapers(), [], "Expected clear to leave no stored wallpaper assignments")
}

private func testStoredWallpaperPersistenceRetainsDisplayMetadata() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-metadata")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "display-metadata.png")
    defaults.replaceReusableGeneratedWallpapers([
        StoredGeneratedWallpaper(
            targetIdentifier: "display-a",
            fileURL: wallpaperURL,
            pixelWidth: 1920,
            pixelHeight: 1080,
            backingScaleFactor: 2.0,
            originX: -1920,
            originY: 0
        )
    ])

    let storedWallpapers = defaults.loadReusableGeneratedWallpapers()
    expectEqual(storedWallpapers.count, 1, "Expected stored wallpaper metadata round-trip to preserve the assignment")
    expectEqual(storedWallpapers[0].pixelWidth, 1920, "Expected persisted pixel width to survive round-trip")
    expectEqual(storedWallpapers[0].pixelHeight, 1080, "Expected persisted pixel height to survive round-trip")
    expectEqual(storedWallpapers[0].backingScaleFactor, 2.0, "Expected persisted scale factor to survive round-trip")
    expectEqual(storedWallpapers[0].originX, -1920, "Expected persisted origin X to survive round-trip")
    expectEqual(storedWallpapers[0].originY, 0, "Expected persisted origin Y to survive round-trip")
}

private func testFullRestoreForAllScreensWallpaper() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-all")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "all.png")
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a"),
        makeResolvedScreen(screen: "screen-b", identifier: "display-b")
    ]

    var applied: [(String, URL)] = []
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(
                targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                fileURL: wallpaperURL
            )
        ],
        resolvedScreens: screens,
        setDesktopImage: { url, screen in
            applied.append((screen, url))
        }
    )

    expectEqual(outcome, .fullRestore, "Expected all-screens wallpaper to report a full restore")
    expectEqual(outcome.didRestore, true, "Expected full restore to report that wallpapers were restored")
    expectEqual(applied.count, 2, "Expected all connected screens to receive the restored wallpaper")
    expectEqual(applied[0].0, "screen-a", "Expected first connected screen to be restored")
    expectEqual(applied[1].0, "screen-b", "Expected second connected screen to be restored")
}

private func testFullRestoreForTargetedScreens() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-targeted")
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = makeWallpaper(directory: directory, name: "display-a.png")
    let secondURL = makeWallpaper(directory: directory, name: "display-b.png")
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a"),
        makeResolvedScreen(screen: "screen-b", identifier: "display-b")
    ]

    var applied: [(String, URL)] = []
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: firstURL),
            StoredGeneratedWallpaper(targetIdentifier: "display-b", fileURL: secondURL)
        ],
        resolvedScreens: screens,
        setDesktopImage: { url, screen in
            applied.append((screen, url))
        }
    )

    expectEqual(outcome, .fullRestore, "Expected matching targeted wallpapers to report a full restore")
    expectEqual(applied.count, 2, "Expected all stored targeted wallpapers to be applied")
    expectEqual(applied[0].1.standardizedFileURL, firstURL.standardizedFileURL, "Expected first target to keep its stored wallpaper")
    expectEqual(applied[1].1.standardizedFileURL, secondURL.standardizedFileURL, "Expected second target to keep its stored wallpaper")
}

private func testPartialRestoreWhenTopologyIsReduced() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-partial")
    defer { try? FileManager.default.removeItem(at: directory) }

    let firstURL = makeWallpaper(directory: directory, name: "display-a.png")
    let secondURL = makeWallpaper(directory: directory, name: "display-b.png")
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a")
    ]

    var applied: [(String, URL)] = []
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: firstURL),
            StoredGeneratedWallpaper(targetIdentifier: "display-b", fileURL: secondURL)
        ],
        resolvedScreens: screens,
        setDesktopImage: { url, screen in
            applied.append((screen, url))
        }
    )

    expectEqual(outcome, .partialRestore, "Expected reduced topology restore to report partial restore")
    expectEqual(outcome.didRestore, true, "Expected partial restore to report that some wallpapers were restored")
    expectEqual(applied.count, 1, "Expected only connected matching screens to receive wallpapers")
    expectEqual(applied[0].0, "screen-a", "Expected matching connected screen to keep its wallpaper")
}

private func testNoStoredWallpaperOutcome() {
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a")
    ]

    var applyCallCount = 0
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [],
        resolvedScreens: screens,
        setDesktopImage: { _, _ in
            applyCallCount += 1
        }
    )

    expectEqual(outcome, .noStoredWallpapers, "Expected empty stored wallpaper state to be explicit")
    expectEqual(outcome.didRestore, false, "Expected no stored wallpapers to report no restore work")
    expectEqual(applyCallCount, 0, "Expected empty storage to skip wallpaper application")
}

private func testNoConnectedScreensOutcome() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-noscreens")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "all.png")
    var applyCallCount = 0
    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(
                targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                fileURL: wallpaperURL
            )
        ],
        resolvedScreens: [WallpaperSetter.ResolvedScreen<String>](),
        setDesktopImage: { (_: URL, _: String) in
            applyCallCount += 1
        }
    )

    expectEqual(outcome, .noConnectedScreens, "Expected explicit no-screen restore outcome")
    expectEqual(outcome.didRestore, false, "Expected no connected screens to report no restore work")
    expectEqual(applyCallCount, 0, "Expected missing connected screens to skip wallpaper application")
}

private enum TestError: Error {
    case applyFailed
}

@MainActor
private final class ManualRestoreScheduler {
    struct Entry {
        let generation: UInt64
        let delay: TimeInterval
        let operation: @MainActor (UInt64) -> Void
    }

    private(set) var entries: [Entry] = []

    func schedule(
        generation: UInt64,
        delay: TimeInterval,
        operation: @escaping @MainActor (UInt64) -> Void
    ) {
        entries.append(Entry(generation: generation, delay: delay, operation: operation))
    }

    func fire(at index: Int) {
        let entry = entries[index]
        entry.operation(entry.generation)
    }
}

@MainActor
private func makeRestoreTestingAppState(
    reapplyStoredWallpaper: @escaping AppState.ReapplyStoredWallpaper
) -> AppState {
    AppState(
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in
            fail("Expected display topology restore tests not to generate new wallpapers")
        },
        setWallpaper: { _ in
            fail("Expected display topology restore tests not to use the rotation apply path")
        },
        reapplyStoredWallpaper: reapplyStoredWallpaper,
        markHighlightShown: { _ in
            fail("Expected display topology restore tests not to mark highlights")
        }
    )
}

private func testApplyFailureOutcome() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-failure")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "all.png")
    let screens = [
        makeResolvedScreen(screen: "screen-a", identifier: "display-a")
    ]

    let outcome = WallpaperSetter.restoreStoredWallpapers(
        [
            StoredGeneratedWallpaper(
                targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                fileURL: wallpaperURL
            )
        ],
        resolvedScreens: screens,
        setDesktopImage: { _, _ in
            throw TestError.applyFailed
        }
    )

    expectEqual(outcome, .applyFailure, "Expected thrown apply errors to map to applyFailure")
    expectEqual(outcome.didRestore, false, "Expected apply failure to report no completed restore")
}

private func testResolverRemapsWhenMainDisplayChanges() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-main-display")
    defer { try? FileManager.default.removeItem(at: directory) }

    let leftURL = makeWallpaper(directory: directory, name: "left.png")
    let rightURL = makeWallpaper(directory: directory, name: "right.png")
    let screens = [
        makeResolvedScreen(
            screen: "left-screen",
            identifier: "display-22",
            pixelWidth: 1440,
            pixelHeight: 900,
            originX: -1440,
            originY: 0
        ),
        makeResolvedScreen(
            screen: "right-screen",
            identifier: "display-11",
            pixelWidth: 1920,
            pixelHeight: 1080,
            originX: 0,
            originY: 0
        )
    ]

    let plan = DisplayIdentityResolver.resolvedAssignments(
        for: [
            StoredGeneratedWallpaper(
                targetIdentifier: "display-11",
                fileURL: leftURL,
                pixelWidth: 1440,
                pixelHeight: 900,
                backingScaleFactor: 1.0,
                originX: 0,
                originY: 0
            ),
            StoredGeneratedWallpaper(
                targetIdentifier: "display-22",
                fileURL: rightURL,
                pixelWidth: 1920,
                pixelHeight: 1080,
                backingScaleFactor: 1.0,
                originX: 1440,
                originY: 0
            )
        ],
        resolvedScreens: screens
    )

    expectEqual(plan.expectedAssignmentCount, 2, "Expected both stored displays to participate in remapping")
    expectEqual(plan.assignments.count, 2, "Expected both wallpapers to remap after a main-display identifier swap")
    expectEqual(plan.assignments[0].screenIdentifier, "display-22", "Expected left wallpaper to follow the physical left display")
    expectEqual(plan.assignments[1].screenIdentifier, "display-11", "Expected right wallpaper to follow the physical right display")
}

private func testResolverIgnoresScreenOrderingChanges() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-reorder")
    defer { try? FileManager.default.removeItem(at: directory) }

    let topURL = makeWallpaper(directory: directory, name: "top.png")
    let bottomURL = makeWallpaper(directory: directory, name: "bottom.png")
    let screens = [
        makeResolvedScreen(
            screen: "bottom-screen",
            identifier: "display-bottom-new",
            pixelWidth: 1200,
            pixelHeight: 1600,
            originX: 0,
            originY: -1600
        ),
        makeResolvedScreen(
            screen: "top-screen",
            identifier: "display-top-new",
            pixelWidth: 1200,
            pixelHeight: 1600,
            originX: 0,
            originY: 0
        )
    ]

    let plan = DisplayIdentityResolver.resolvedAssignments(
        for: [
            StoredGeneratedWallpaper(
                targetIdentifier: "display-top-old",
                fileURL: topURL,
                pixelWidth: 1200,
                pixelHeight: 1600,
                backingScaleFactor: 1.0,
                originX: 0,
                originY: 1200
            ),
            StoredGeneratedWallpaper(
                targetIdentifier: "display-bottom-old",
                fileURL: bottomURL,
                pixelWidth: 1200,
                pixelHeight: 1600,
                backingScaleFactor: 1.0,
                originX: 0,
                originY: -400
            )
        ],
        resolvedScreens: screens
    )

    expectEqual(plan.assignments.count, 2, "Expected topology remapping to ignore current screen array order")
    expectEqual(plan.assignments[0].screenIdentifier, "display-top-new", "Expected top wallpaper to remain on the top display")
    expectEqual(plan.assignments[1].screenIdentifier, "display-bottom-new", "Expected bottom wallpaper to remain on the bottom display")
}

private func testResolverKeepsSameResolutionDisplaysDistinct() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-same-resolution")
    defer { try? FileManager.default.removeItem(at: directory) }

    let leftURL = makeWallpaper(directory: directory, name: "same-left.png")
    let rightURL = makeWallpaper(directory: directory, name: "same-right.png")
    let screens = [
        makeResolvedScreen(
            screen: "left-screen",
            identifier: "display-left-new",
            pixelWidth: 1920,
            pixelHeight: 1080,
            originX: 0,
            originY: 0
        ),
        makeResolvedScreen(
            screen: "right-screen",
            identifier: "display-right-new",
            pixelWidth: 1920,
            pixelHeight: 1080,
            originX: 1920,
            originY: 0
        )
    ]

    let plan = DisplayIdentityResolver.resolvedAssignments(
        for: [
            StoredGeneratedWallpaper(
                targetIdentifier: "display-a",
                fileURL: leftURL,
                pixelWidth: 1920,
                pixelHeight: 1080,
                backingScaleFactor: 1.0,
                originX: 0,
                originY: 0
            ),
            StoredGeneratedWallpaper(
                targetIdentifier: "display-b",
                fileURL: rightURL,
                pixelWidth: 1920,
                pixelHeight: 1080,
                backingScaleFactor: 1.0,
                originX: 1920,
                originY: 0
            )
        ],
        resolvedScreens: screens
    )

    expectEqual(plan.assignments.count, 2, "Expected both same-resolution displays to remap distinctly")
    expectEqual(plan.assignments[0].screenIdentifier, "display-left-new", "Expected left display to remain distinguishable by position")
    expectEqual(plan.assignments[1].screenIdentifier, "display-right-new", "Expected right display to remain distinguishable by position")
}

private func testResolverHandlesMissingDisplaysWithoutMisapplying() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-missing")
    defer { try? FileManager.default.removeItem(at: directory) }

    let primaryURL = makeWallpaper(directory: directory, name: "primary.png")
    let secondaryURL = makeWallpaper(directory: directory, name: "secondary.png")
    let screens = [
        makeResolvedScreen(
            screen: "primary-screen",
            identifier: "display-primary-new",
            pixelWidth: 1440,
            pixelHeight: 900,
            originX: 0,
            originY: 0
        )
    ]

    let plan = DisplayIdentityResolver.resolvedAssignments(
        for: [
            StoredGeneratedWallpaper(
                targetIdentifier: "display-primary-old",
                fileURL: primaryURL,
                pixelWidth: 1440,
                pixelHeight: 900,
                backingScaleFactor: 1.0,
                originX: 0,
                originY: 0
            ),
            StoredGeneratedWallpaper(
                targetIdentifier: "display-secondary-old",
                fileURL: secondaryURL,
                pixelWidth: 1920,
                pixelHeight: 1080,
                backingScaleFactor: 1.0,
                originX: 1440,
                originY: 0
            )
        ],
        resolvedScreens: screens
    )

    expectEqual(plan.expectedAssignmentCount, 2, "Expected missing-display restores to preserve the original target count")
    expectEqual(plan.assignments.count, 1, "Expected only the surviving display to receive a remapped wallpaper")
    expectEqual(plan.assignments[0].screenIdentifier, "display-primary-new", "Expected the surviving physical display to retain its wallpaper")
}

private func testResolverHandlesExtraDisplaysWithoutBreakingKnownMappings() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-extra")
    defer { try? FileManager.default.removeItem(at: directory) }

    let mainURL = makeWallpaper(directory: directory, name: "main.png")
    let sideURL = makeWallpaper(directory: directory, name: "side.png")
    let screens = [
        makeResolvedScreen(
            screen: "main-screen",
            identifier: "display-main-new",
            pixelWidth: 1512,
            pixelHeight: 982,
            backingScaleFactor: 2.0,
            originX: 0,
            originY: 0
        ),
        makeResolvedScreen(
            screen: "side-screen",
            identifier: "display-side-new",
            pixelWidth: 1920,
            pixelHeight: 1080,
            originX: 1512,
            originY: 0
        ),
        makeResolvedScreen(
            screen: "extra-screen",
            identifier: "display-extra",
            pixelWidth: 1280,
            pixelHeight: 800,
            originX: -1280,
            originY: 0
        )
    ]

    let plan = DisplayIdentityResolver.resolvedAssignments(
        for: [
            StoredGeneratedWallpaper(
                targetIdentifier: "display-main-old",
                fileURL: mainURL,
                pixelWidth: 1512,
                pixelHeight: 982,
                backingScaleFactor: 2.0,
                originX: 0,
                originY: 0
            ),
            StoredGeneratedWallpaper(
                targetIdentifier: "display-side-old",
                fileURL: sideURL,
                pixelWidth: 1920,
                pixelHeight: 1080,
                backingScaleFactor: 1.0,
                originX: 1512,
                originY: 0
            )
        ],
        resolvedScreens: screens
    )

    expectEqual(plan.assignments.count, 2, "Expected known displays to remain mappable even when a new display is present")
    expectEqual(plan.assignments[0].screenIdentifier, "display-main-new", "Expected the original main display mapping to survive the extra display")
    expectEqual(plan.assignments[1].screenIdentifier, "display-side-new", "Expected the original side display mapping to survive the extra display")
}

@MainActor
private func testDisplayTopologyCoordinatorDebouncesWakeThenReconfiguration() {
    let wakeNotificationName = Notification.Name("verify-t64-wake")
    let displayNotificationName = Notification.Name("verify-t64-display")
    let wakeCenter = NotificationCenter()
    let displayCenter = NotificationCenter()
    let scheduler = ManualRestoreScheduler()
    var reapplyCallCount = 0
    let appState = makeRestoreTestingAppState {
        reapplyCallCount += 1
        return .partialRestore
    }

    let coordinator = DisplayTopologyCoordinator(
        appState: appState,
        notificationCenter: wakeCenter,
        wakeNotificationName: wakeNotificationName,
        displayReconfigurationNotificationCenter: displayCenter,
        displayReconfigurationNotificationName: displayNotificationName,
        debounceInterval: 0.25,
        scheduleRestore: scheduler.schedule(generation:delay:operation:)
    )

    coordinator.start()
    wakeCenter.post(name: wakeNotificationName, object: nil)
    displayCenter.post(name: displayNotificationName, object: nil)

    expectEqual(scheduler.entries.count, 2, "Expected wake plus reconfiguration to schedule two debounced restore attempts")
    expectEqual(scheduler.entries[0].delay, 0.25, "Expected wake restore scheduling to use the configured debounce interval")
    expectEqual(scheduler.entries[1].delay, 0.25, "Expected display reconfiguration scheduling to use the configured debounce interval")

    scheduler.fire(at: 0)
    expectEqual(reapplyCallCount, 0, "Expected the wake-triggered restore to be dropped after a later reconfiguration arrives")

    scheduler.fire(at: 1)
    expectEqual(reapplyCallCount, 1, "Expected wake-then-reconfigure bursts to coalesce into one restore pass")
}

@MainActor
private func testDisplayTopologyCoordinatorDebouncesRepeatedReconfigurationBursts() {
    let scheduler = ManualRestoreScheduler()
    var reapplyCallCount = 0
    let appState = makeRestoreTestingAppState {
        reapplyCallCount += 1
        return .fullRestore
    }

    let coordinator = DisplayTopologyCoordinator(
        appState: appState,
        notificationCenter: NotificationCenter(),
        wakeNotificationName: Notification.Name("unused-wake"),
        displayReconfigurationNotificationCenter: NotificationCenter(),
        displayReconfigurationNotificationName: Notification.Name("unused-display"),
        debounceInterval: 0.5,
        scheduleRestore: scheduler.schedule(generation:delay:operation:)
    )

    coordinator.handleDisplayReconfigurationNotification()
    coordinator.handleDisplayReconfigurationNotification()
    coordinator.handleDisplayReconfigurationNotification()

    expectEqual(scheduler.entries.count, 3, "Expected each reconfiguration event to replace the pending debounced restore")

    scheduler.fire(at: 0)
    scheduler.fire(at: 1)
    expectEqual(reapplyCallCount, 0, "Expected superseded reconfiguration events not to restore early")

    scheduler.fire(at: 2)
    expectEqual(reapplyCallCount, 1, "Expected a burst of repeated reconfiguration events to restore once after topology settles")
}

@MainActor
private func testDisplayTopologyCoordinatorStopInvalidatesPendingRestore() {
    let scheduler = ManualRestoreScheduler()
    var reapplyCallCount = 0
    let appState = makeRestoreTestingAppState {
        reapplyCallCount += 1
        return .fullRestore
    }

    let coordinator = DisplayTopologyCoordinator(
        appState: appState,
        notificationCenter: NotificationCenter(),
        wakeNotificationName: Notification.Name("unused-wake"),
        displayReconfigurationNotificationCenter: NotificationCenter(),
        displayReconfigurationNotificationName: Notification.Name("unused-display"),
        debounceInterval: 0.5,
        scheduleRestore: scheduler.schedule(generation:delay:operation:)
    )

    coordinator.handleWakeNotification()
    expectEqual(scheduler.entries.count, 1, "Expected wake handling to schedule a debounced restore")

    coordinator.stop()
    scheduler.fire(at: 0)

    expectEqual(reapplyCallCount, 0, "Expected stop() to invalidate already scheduled restore passes")
}

@MainActor
private func testAppStateReapplyForwardsStructuredOutcome() {
    var reapplyCallCount = 0
    var markHighlightShownCount = 0

    let appState = AppState(
        pickNextHighlight: {
            fail("Expected wake restore not to request a new highlight")
        },
        generateWallpaper: { _, _ in
            fail("Expected wake restore not to generate a new wallpaper")
        },
        setWallpaper: { _ in
            fail("Expected wake restore not to use the rotation apply path")
        },
        reapplyStoredWallpaper: {
            reapplyCallCount += 1
            return .partialRestore
        },
        markHighlightShown: { _ in
            markHighlightShownCount += 1
        }
    )

    let outcome = appState.reapplyStoredWallpaperIfAvailable()
    expectEqual(outcome, .partialRestore, "Expected AppState wake restore to forward the structured outcome")
    expectEqual(reapplyCallCount, 1, "Expected AppState wake restore to delegate exactly once")
    expectEqual(markHighlightShownCount, 0, "Expected wake restore not to advance rotation state")
}

@MainActor
private func testAppStateRotationUsesReplacePersistenceOnly() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-appstate-replace")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "applied.png")
    var replacedWallpapers: [[AppState.GeneratedWallpaper]] = []
    var mergeCallCount = 0
    var clearCallCount = 0
    var markedHighlights: [UUID] = []

    let appState = AppState(
        pickNextHighlight: { makeHighlight(quoteText: "Persist through replace") },
        generateWallpaper: { _, _ in wallpaperURL },
        setWallpaper: { _ in },
        storedWallpaperAssignmentPersistence: AppState.StoredWallpaperAssignmentPersistence(
            replace: { wallpapers in
                replacedWallpapers.append(wallpapers)
            },
            merge: { _ in
                mergeCallCount += 1
            },
            clear: {
                clearCallCount += 1
            }
        ),
        markHighlightShown: { markedHighlights.append($0) }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(outcome, .success, "Expected successful rotation to report success")
    expectEqual(replacedWallpapers.count, 1, "Expected successful rotation to persist through replace exactly once")
    expectEqual(
        replacedWallpapers[0],
        [
            AppState.GeneratedWallpaper(
                targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                fileURL: wallpaperURL
            )
        ],
        "Expected successful single-screen rotation to persist the all-screens assignment"
    )
    expectEqual(mergeCallCount, 0, "Expected successful rotation not to merge persisted assignments")
    expectEqual(clearCallCount, 0, "Expected successful rotation not to clear persisted assignments")
    expectEqual(markedHighlights.count, 1, "Expected successful rotation to mark the selected highlight as shown")
}

@MainActor
private func testAppStateRotationFailureSkipsPersistenceOperations() {
    var replaceCallCount = 0
    var mergeCallCount = 0
    var clearCallCount = 0
    var markHighlightShownCount = 0

    let appState = AppState(
        pickNextHighlight: { makeHighlight(quoteText: "Do not persist") },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/failed.png") },
        setWallpaper: { _ in
            throw TestError.applyFailed
        },
        storedWallpaperAssignmentPersistence: AppState.StoredWallpaperAssignmentPersistence(
            replace: { _ in
                replaceCallCount += 1
            },
            merge: { _ in
                mergeCallCount += 1
            },
            clear: {
                clearCallCount += 1
            }
        ),
        markHighlightShown: { _ in
            markHighlightShownCount += 1
        }
    )

    let outcome = appState.rotateWallpaperWithOutcome()
    expectEqual(
        outcome,
        .wallpaperApplyFailure(.applyError),
        "Expected apply failures to be surfaced without mutating persisted assignments"
    )
    expectEqual(replaceCallCount, 0, "Expected failed rotation not to replace persisted assignments")
    expectEqual(mergeCallCount, 0, "Expected failed rotation not to merge persisted assignments")
    expectEqual(clearCallCount, 0, "Expected failed rotation not to clear persisted assignments")
    expectEqual(markHighlightShownCount, 0, "Expected failed rotation not to mark highlights as shown")
}

@MainActor
private func testAppStateExplicitMergeAndClearForwardToPersistenceBoundary() {
    let directory = makeTemporaryDirectory(prefix: "kindlewall-t64-appstate-explicit")
    defer { try? FileManager.default.removeItem(at: directory) }

    let wallpaperURL = makeWallpaper(directory: directory, name: "merged.png")
    let mergedWallpaper = AppState.GeneratedWallpaper(targetIdentifier: "display-a", fileURL: wallpaperURL)
    var mergedWallpapers: [[AppState.GeneratedWallpaper]] = []
    var clearCallCount = 0

    let appState = AppState(
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in
            fail("Expected explicit persistence forwarding test not to rotate wallpapers")
        },
        setWallpaper: { _ in
            fail("Expected explicit persistence forwarding test not to apply wallpapers")
        },
        storedWallpaperAssignmentPersistence: AppState.StoredWallpaperAssignmentPersistence(
            replace: { _ in
                fail("Expected explicit merge/clear forwarding not to call replace")
            },
            merge: { wallpapers in
                mergedWallpapers.append(wallpapers)
            },
            clear: {
                clearCallCount += 1
            }
        ),
        markHighlightShown: { _ in
            fail("Expected explicit persistence forwarding test not to mark highlights")
        }
    )

    appState.mergeStoredWallpaperAssignments([mergedWallpaper])
    appState.clearStoredWallpaperAssignments()

    expectEqual(mergedWallpapers, [[mergedWallpaper]], "Expected AppState.mergeStoredWallpaperAssignments to forward the generated wallpapers unchanged")
    expectEqual(clearCallCount, 1, "Expected AppState.clearStoredWallpaperAssignments to forward exactly once")
}

testReplaceReusableGeneratedWallpapersReplacesStoredSnapshot()
testMergeReusableGeneratedWallpapersMergesByTargetIdentifier()
testClearReusableGeneratedWallpapersRemovesStoredAssignments()
testStoredWallpaperPersistenceRetainsDisplayMetadata()
testFullRestoreForAllScreensWallpaper()
testFullRestoreForTargetedScreens()
testPartialRestoreWhenTopologyIsReduced()
testNoStoredWallpaperOutcome()
testNoConnectedScreensOutcome()
testApplyFailureOutcome()
testResolverRemapsWhenMainDisplayChanges()
testResolverIgnoresScreenOrderingChanges()
testResolverKeepsSameResolutionDisplaysDistinct()
testResolverHandlesMissingDisplaysWithoutMisapplying()
testResolverHandlesExtraDisplaysWithoutBreakingKnownMappings()

await MainActor.run {
    testDisplayTopologyCoordinatorDebouncesWakeThenReconfiguration()
    testDisplayTopologyCoordinatorDebouncesRepeatedReconfigurationBursts()
    testDisplayTopologyCoordinatorStopInvalidatesPendingRestore()
    testAppStateReapplyForwardsStructuredOutcome()
    testAppStateRotationUsesReplacePersistenceOnly()
    testAppStateRotationFailureSkipsPersistenceOperations()
    testAppStateExplicitMergeAndClearForwardToPersistenceBoundary()
}

print("verify_t64_main passed")
