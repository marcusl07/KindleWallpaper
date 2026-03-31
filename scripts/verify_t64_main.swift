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
    identifier: String
) -> WallpaperSetter.ResolvedScreen<String> {
    WallpaperSetter.ResolvedScreen(
        screen: screen,
        identifier: identifier,
        pixelWidth: 1,
        pixelHeight: 1
    )
}

private func makeWallpaper(directory: URL, name: String) -> URL {
    let fileURL = directory.appendingPathComponent(name, isDirectory: false)
    FileManager.default.createFile(atPath: fileURL.path, contents: Data(name.utf8))
    return fileURL
}

@MainActor
private func makeWakeRestoreAppState(
    reapplyStoredWallpaper: @escaping () -> WallpaperSetter.RestoreOutcome,
    markHighlightShown: @escaping (UUID) -> Void = { _ in
        fail("Expected wake restore not to advance rotation state")
    }
) -> AppState {
    AppState(
        pickNextHighlight: {
            fail("Expected wake restore not to request a new highlight")
        },
        generateWallpaper: { _, _ in
            fail("Expected wake restore not to generate a new wallpaper")
        },
        setWallpaper: { _ in
            fail("Expected wake restore not to use the rotation apply path")
        },
        reapplyStoredWallpaper: reapplyStoredWallpaper,
        markHighlightShown: markHighlightShown
    )
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

@MainActor
private func testDisplayTopologyCoordinatorRestoresOnWakeNotification() {
    let notificationCenter = NotificationCenter()
    let wakeNotificationName = Notification.Name("verify-t64-display-wake")
    var reapplyCallCount = 0
    let appState = makeWakeRestoreAppState(
        reapplyStoredWallpaper: {
            reapplyCallCount += 1
            return .fullRestore
        }
    )

    let coordinator = DisplayTopologyCoordinator(
        appState: appState,
        notificationCenter: notificationCenter,
        wakeNotificationName: wakeNotificationName
    )

    coordinator.start()
    notificationCenter.post(name: wakeNotificationName, object: nil)

    expectEqual(reapplyCallCount, 1, "Expected wake notifications to trigger exactly one restore")
}

@MainActor
private func testDisplayTopologyCoordinatorStartIsIdempotent() {
    let notificationCenter = NotificationCenter()
    let wakeNotificationName = Notification.Name("verify-t64-display-wake-idempotent")
    var reapplyCallCount = 0
    let appState = makeWakeRestoreAppState(
        reapplyStoredWallpaper: {
            reapplyCallCount += 1
            return .partialRestore
        }
    )

    let coordinator = DisplayTopologyCoordinator(
        appState: appState,
        notificationCenter: notificationCenter,
        wakeNotificationName: wakeNotificationName
    )

    coordinator.start()
    coordinator.start()
    notificationCenter.post(name: wakeNotificationName, object: nil)

    expectEqual(reapplyCallCount, 1, "Expected repeated coordinator starts not to duplicate wake observers")
}

@MainActor
private func testDisplayTopologyCoordinatorUsesLatestAppState() {
    let notificationCenter = NotificationCenter()
    let wakeNotificationName = Notification.Name("verify-t64-display-wake-updated-state")
    var firstAppStateCallCount = 0
    var secondAppStateCallCount = 0
    let firstAppState = makeWakeRestoreAppState(
        reapplyStoredWallpaper: {
            firstAppStateCallCount += 1
            return .partialRestore
        }
    )
    let secondAppState = makeWakeRestoreAppState(
        reapplyStoredWallpaper: {
            secondAppStateCallCount += 1
            return .fullRestore
        }
    )

    let coordinator = DisplayTopologyCoordinator(
        appState: firstAppState,
        notificationCenter: notificationCenter,
        wakeNotificationName: wakeNotificationName
    )

    coordinator.start()
    coordinator.setAppState(secondAppState)
    notificationCenter.post(name: wakeNotificationName, object: nil)

    expectEqual(firstAppStateCallCount, 0, "Expected coordinator to stop using stale app state after reconfiguration")
    expectEqual(secondAppStateCallCount, 1, "Expected coordinator to use the latest app state after reconfiguration")
}

testReplaceReusableGeneratedWallpapersReplacesStoredSnapshot()
testMergeReusableGeneratedWallpapersMergesByTargetIdentifier()
testClearReusableGeneratedWallpapersRemovesStoredAssignments()
testFullRestoreForAllScreensWallpaper()
testFullRestoreForTargetedScreens()
testPartialRestoreWhenTopologyIsReduced()
testNoStoredWallpaperOutcome()
testNoConnectedScreensOutcome()
testApplyFailureOutcome()

await MainActor.run {
    testAppStateReapplyForwardsStructuredOutcome()
    testAppStateRotationUsesReplacePersistenceOnly()
    testAppStateRotationFailureSkipsPersistenceOperations()
    testAppStateExplicitMergeAndClearForwardToPersistenceBoundary()
    testDisplayTopologyCoordinatorRestoresOnWakeNotification()
    testDisplayTopologyCoordinatorStartIsIdempotent()
    testDisplayTopologyCoordinatorUsesLatestAppState()
}

print("verify_t64_main passed")
