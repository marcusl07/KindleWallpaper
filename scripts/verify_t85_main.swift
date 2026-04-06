import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t85_main failed: \(message)\n", stderr)
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

private func makeResolvedScreen(
    screen: String,
    identifier: String
) -> WallpaperSetter.ResolvedScreen<String> {
    WallpaperSetter.ResolvedScreen(
        screen: screen,
        identifier: identifier,
        pixelWidth: 1920,
        pixelHeight: 1080
    )
}

private func makeWallpaperURL(name: String) -> URL {
    URL(fileURLWithPath: "/tmp/\(name).png").standardizedFileURL
}

@MainActor
private func testTopologyReapplyUsesMainScreenWallpaperAcrossConnectedScreens() {
    let mainWallpaperURL = makeWallpaperURL(name: "t85-main")
    let externalWallpaperURL = makeWallpaperURL(name: "t85-external")
    let resolvedScreens = [
        makeResolvedScreen(screen: "main-screen", identifier: "display-main"),
        makeResolvedScreen(screen: "external-screen", identifier: "display-external")
    ]

    let currentImagesByScreen: [String: URL] = [
        "main-screen": mainWallpaperURL,
        "external-screen": externalWallpaperURL
    ]
    var appliedAssignments: [(String, URL)] = []

    let outcome = AppState.reapplyCurrentWallpaperForTopology(
        resolvedScreens: resolvedScreens,
        preferredSourceScreen: "main-screen",
        sameScreen: ==,
        currentDesktopImageURL: { currentImagesByScreen[$0] },
        setDesktopImage: { url, screen in
            appliedAssignments.append((screen, url.standardizedFileURL))
        }
    )

    expectEqual(outcome, .reapplied, "Expected topology reapply to use the main screen wallpaper as the shared source")
    expectEqual(appliedAssignments.count, 1, "Expected only mismatched screens to be updated")
    expectEqual(appliedAssignments[0].0, "external-screen", "Expected the external screen to receive the shared wallpaper")
    expectEqual(
        appliedAssignments[0].1,
        mainWallpaperURL,
        "Expected the shared wallpaper to come from the main screen"
    )
}

@MainActor
private func testTopologyReapplyFallsBackToFirstConnectedScreenWallpaper() {
    let firstWallpaperURL = makeWallpaperURL(name: "t85-first")
    let secondWallpaperURL = makeWallpaperURL(name: "t85-second")
    let resolvedScreens = [
        makeResolvedScreen(screen: "first-screen", identifier: "display-first"),
        makeResolvedScreen(screen: "second-screen", identifier: "display-second")
    ]

    let currentImagesByScreen: [String: URL] = [
        "first-screen": firstWallpaperURL,
        "second-screen": secondWallpaperURL
    ]
    var appliedAssignments: [(String, URL)] = []

    let outcome = AppState.reapplyCurrentWallpaperForTopology(
        resolvedScreens: resolvedScreens,
        preferredSourceScreen: "missing-main-screen",
        sameScreen: ==,
        currentDesktopImageURL: { currentImagesByScreen[$0] },
        setDesktopImage: { url, screen in
            appliedAssignments.append((screen, url.standardizedFileURL))
        }
    )

    expectEqual(outcome, .reapplied, "Expected topology reapply to fall back to the first connected screen")
    expectEqual(appliedAssignments.count, 1, "Expected only mismatched screens to be updated during fallback")
    expectEqual(appliedAssignments[0].0, "second-screen", "Expected the second screen to receive the fallback wallpaper")
    expectEqual(
        appliedAssignments[0].1,
        firstWallpaperURL,
        "Expected fallback reapply to use the first connected screen wallpaper"
    )
}

@MainActor
private func testTopologyReapplyReportsAlreadyAppliedWhenAllScreensMatch() {
    let sharedWallpaperURL = makeWallpaperURL(name: "t85-shared")
    let resolvedScreens = [
        makeResolvedScreen(screen: "main-screen", identifier: "display-main"),
        makeResolvedScreen(screen: "external-screen", identifier: "display-external")
    ]

    let currentImagesByScreen: [String: URL] = [
        "main-screen": sharedWallpaperURL,
        "external-screen": sharedWallpaperURL
    ]
    var applyCallCount = 0

    let outcome = AppState.reapplyCurrentWallpaperForTopology(
        resolvedScreens: resolvedScreens,
        preferredSourceScreen: "main-screen",
        sameScreen: ==,
        currentDesktopImageURL: { currentImagesByScreen[$0] },
        setDesktopImage: { _, _ in
            applyCallCount += 1
        }
    )

    expectEqual(outcome, .alreadyApplied, "Expected explicit no-op outcome when all screens already show the shared wallpaper")
    expectEqual(applyCallCount, 0, "Expected no-op topology reapply not to call through to wallpaper application")
}

@MainActor
private func testTopologyReapplyReportsNoConnectedScreens() {
    let outcome = AppState.reapplyCurrentWallpaperForTopology(
        resolvedScreens: [],
        preferredSourceScreen: nil as String?,
        sameScreen: ==,
        currentDesktopImageURL: { _ in
            fail("Expected no-connected-screens path not to query desktop image URLs")
        },
        setDesktopImage: { (_: URL, _: String) in
            fail("Expected no-connected-screens path not to apply wallpapers")
        }
    )

    expectEqual(outcome, .noConnectedScreens, "Expected explicit outcome for empty topology")
}

@MainActor
private func testTopologyReapplyReportsNoCurrentWallpaper() {
    let resolvedScreens = [
        makeResolvedScreen(screen: "main-screen", identifier: "display-main"),
        makeResolvedScreen(screen: "external-screen", identifier: "display-external")
    ]

    let outcome = AppState.reapplyCurrentWallpaperForTopology(
        resolvedScreens: resolvedScreens,
        preferredSourceScreen: "main-screen",
        sameScreen: ==,
        currentDesktopImageURL: { _ in nil },
        setDesktopImage: { (_: URL, _: String) in
            fail("Expected no-current-wallpaper path not to apply wallpapers")
        }
    )

    expectEqual(outcome, .noCurrentWallpaper, "Expected explicit outcome when no readable source wallpaper exists")
}

@MainActor
private func testTopologyReapplyReportsApplyFailure() {
    let sharedWallpaperURL = makeWallpaperURL(name: "t85-shared-apply-failure")
    let resolvedScreens = [
        makeResolvedScreen(screen: "main-screen", identifier: "display-main"),
        makeResolvedScreen(screen: "external-screen", identifier: "display-external")
    ]

    let currentImagesByScreen: [String: URL] = [
        "main-screen": sharedWallpaperURL
    ]

    let outcome = AppState.reapplyCurrentWallpaperForTopology(
        resolvedScreens: resolvedScreens,
        preferredSourceScreen: "main-screen",
        sameScreen: ==,
        currentDesktopImageURL: { currentImagesByScreen[$0] },
        setDesktopImage: { _, _ in
            throw TestError.applyFailed
        }
    )

    expectEqual(outcome, .applyFailure, "Expected explicit failure outcome when shared wallpaper application throws")
}

@MainActor
private func testAppStateTopologyReapplyForwardsStructuredOutcome() {
    var reapplyCallCount = 0

    let appState = AppState(
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in
            fail("Expected topology reapply test not to generate wallpapers")
        },
        setWallpaper: { _ in
            fail("Expected topology reapply test not to use the rotation apply path")
        },
        reapplyCurrentWallpaperForTopology: {
            reapplyCallCount += 1
            return .alreadyApplied
        },
        markHighlightShown: { _ in
            fail("Expected topology reapply test not to mark highlights")
        }
    )

    let outcome = appState.reapplyCurrentWallpaperForTopologyChange()
    expectEqual(outcome, .alreadyApplied, "Expected AppState to forward the topology-specific reapply outcome")
    expectEqual(reapplyCallCount, 1, "Expected AppState topology reapply to delegate exactly once")
}

private enum TestError: Error {
    case applyFailed
}

@main
struct VerifyT85Main {
    static func main() {
        Task { @MainActor in
            testTopologyReapplyUsesMainScreenWallpaperAcrossConnectedScreens()
            testTopologyReapplyFallsBackToFirstConnectedScreenWallpaper()
            testTopologyReapplyReportsAlreadyAppliedWhenAllScreensMatch()
            testTopologyReapplyReportsNoConnectedScreens()
            testTopologyReapplyReportsNoCurrentWallpaper()
            testTopologyReapplyReportsApplyFailure()
            testAppStateTopologyReapplyForwardsStructuredOutcome()
            print("T85 verification passed")
            exit(0)
        }

        dispatchMain()
    }
}
