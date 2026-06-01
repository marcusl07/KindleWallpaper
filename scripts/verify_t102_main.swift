import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t102_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func assertTrue(_ value: Bool, _ message: String) {
    if !value {
        fail(message)
    }
}

private func makeWallpaper(_ name: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kindlewall-t102-\(UUID().uuidString)-\(name)")
    do {
        try "wallpaper".write(to: url, atomically: true, encoding: .utf8)
    } catch {
        fail("Failed to write wallpaper fixture: \(error)")
    }
    return url
}

private func testRestorerUsesPersistedAssignmentWithNilPreferredScreen() {
    let firstScreenURL = makeWallpaper("first.png")
    let liveURL = makeWallpaper("live.png")
    let screens = [
        WallpaperSetter.ResolvedScreen(screen: "first", identifier: "display-a", pixelWidth: 1, pixelHeight: 1),
        WallpaperSetter.ResolvedScreen(screen: "second", identifier: "display-b", pixelWidth: 1, pixelHeight: 1)
    ]
    var applied: [(URL, String)] = []

    let restorer = WallpaperTopologyRestorer<String>(
        loadStoredWallpapers: {
            [
                StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: firstScreenURL)
            ]
        },
        resolvedScreens: { screens },
        preferredSourceScreen: { nil },
        sameScreen: { $0 == $1 },
        currentDesktopImageURL: { _ in liveURL },
        setDesktopImage: { url, screen in
            applied.append((url, screen))
        }
    )

    assertEqual(restorer.reapply(), WallpaperTopologyReapplyOutcome.reapplied, "Expected nil-preferred helper restorer to reapply persisted wallpaper")
    assertEqual(applied.map(\.1), ["first", "second"], "Expected helper restorer to apply the persisted first-screen source to every screen")
    assertTrue(applied.allSatisfy { $0.0 == firstScreenURL }, "Expected persisted KindleWall assignment to win over live desktop wallpaper")
}

@MainActor
private func testDisplayCoordinatorRunsInjectedRestoreAction() {
    let wakeCenter = NotificationCenter()
    let wakeName = Notification.Name("verify-t102-wake")
    let displayCenter = NotificationCenter()
    let displayName = Notification.Name("verify-t102-display")
    var restoreCount = 0
    var scheduled: [(generation: UInt64, delay: TimeInterval, operation: @MainActor (UInt64) -> Void)] = []

    let coordinator = DisplayTopologyCoordinator(
        restoreAction: {
            restoreCount += 1
            return .reapplied
        },
        notificationCenter: wakeCenter,
        wakeNotificationName: wakeName,
        displayReconfigurationNotificationCenter: displayCenter,
        displayReconfigurationNotificationName: displayName,
        registerDisplayReconfigurationCallback: { _ in nil },
        unregisterDisplayReconfigurationCallback: { _ in },
        scheduleRestore: { generation, delay, operation in
            scheduled.append((generation, delay, operation))
        }
    )

    coordinator.start()
    wakeCenter.post(name: wakeName, object: nil)

    assertEqual(scheduled.map(\.delay), [1.0, 3.0], "Expected helper display coordinator to keep the fast and confirmation restore timings")
    scheduled[0].operation(scheduled[0].generation)
    scheduled[1].operation(scheduled[1].generation)
    assertEqual(restoreCount, 2, "Expected scheduled coordinator passes to call the injected helper restore action")

    displayCenter.post(name: displayName, object: nil)
    assertEqual(scheduled.count, 4, "Expected display notifications to schedule another bounded restore pair")
    coordinator.stop()
}

@main
enum VerifyT102 {
    @MainActor
    static func main() {
        testRestorerUsesPersistedAssignmentWithNilPreferredScreen()
        testDisplayCoordinatorRunsInjectedRestoreAction()
        print("verify_t102_main passed")
    }
}
