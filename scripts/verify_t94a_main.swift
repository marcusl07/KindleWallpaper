import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t94a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func assertNil<T>(_ value: T?, _ message: String) {
    if value != nil {
        fail(message)
    }
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "KindleWall-T94A-\(UUID().uuidString)"
    guard let defaults = UserDefaults(suiteName: suiteName) else {
        fail("Unable to create isolated UserDefaults suite")
    }
    defaults.removePersistentDomain(forName: suiteName)
    defaults.set(suiteName, forKey: "__verifySuiteName")
    return defaults
}

private func clearDefaults(_ defaults: UserDefaults) {
    guard let suiteName = defaults.string(forKey: "__verifySuiteName"), !suiteName.isEmpty else { return }
    defaults.removePersistentDomain(forName: suiteName)
}

@MainActor
private func testLaunchAtLoginStateRefreshAndToggle() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    var storedEnabled = false
    var refreshedEnabled = false
    var setEnabledRequests: [Bool] = []

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 0,
        books: [],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        getLaunchAtLoginEnabled: { storedEnabled },
        refreshLaunchAtLoginEnabled: {
            refreshedEnabled = storedEnabled
            return refreshedEnabled
        },
        setLaunchAtLoginEnabled: { enabled in
            setEnabledRequests.append(enabled)
            storedEnabled = enabled
        }
    )

    assertEqual(appState.isLaunchAtLoginEnabled, false, "Expected launch-at-login to reflect the injected current state")
    assertEqual(appState.launchAtLoginErrorMessage, nil, "Expected launch-at-login error state to start empty")

    appState.setLaunchAtLoginEnabled(true)
    assertEqual(setEnabledRequests, [true], "Expected launch-at-login enable to call the injected setter")
    assertEqual(appState.isLaunchAtLoginEnabled, true, "Expected launch-at-login state to update after enabling")

    storedEnabled = false
    appState.refreshLaunchAtLoginState()
    assertEqual(appState.isLaunchAtLoginEnabled, false, "Expected refresh to reconcile launch-at-login state from the source of truth")
    assertEqual(appState.launchAtLoginErrorMessage, nil, "Expected refresh to clear launch-at-login errors")

    appState.toggleLaunchAtLogin()
    assertEqual(setEnabledRequests, [true, true], "Expected toggle to reuse the setter")
    assertEqual(appState.isLaunchAtLoginEnabled, true, "Expected toggle to invert the launch-at-login state")
}

@MainActor
private func testLaunchAtLoginErrorPropagation() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    var storedEnabled = false
    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 0,
        books: [],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        getLaunchAtLoginEnabled: { storedEnabled },
        refreshLaunchAtLoginEnabled: { storedEnabled },
        setLaunchAtLoginEnabled: { enabled in
            if enabled {
                throw AppState.LaunchAtLoginError.registerFailed("blocked by test")
            }
        }
    )

    appState.setLaunchAtLoginEnabled(true)
    assertEqual(appState.isLaunchAtLoginEnabled, false, "Expected failed enable to preserve the reflected state")
    assertEqual(
        appState.launchAtLoginErrorMessage,
        "blocked by test",
        "Expected launch-at-login register errors to surface to the UI"
    )
}

@MainActor
private func testLaunchAtLoginUnsupportedFallback() {
    let defaults = makeDefaults()
    defer { clearDefaults(defaults) }

    let appState = AppState(
        userDefaults: defaults,
        totalHighlightCount: 0,
        books: [],
        pickNextHighlight: { nil as Highlight? },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        getLaunchAtLoginEnabled: { false },
        refreshLaunchAtLoginEnabled: { false },
        setLaunchAtLoginEnabled: { _ in
            throw AppState.LaunchAtLoginError.unsupported
        }
    )

    appState.setLaunchAtLoginEnabled(true)
    assertEqual(
        appState.launchAtLoginErrorMessage,
        "Launch at login is unavailable on this platform.",
        "Expected unsupported launch-at-login to produce a user-facing error"
    )
}

Task { @MainActor in
    testLaunchAtLoginStateRefreshAndToggle()
    testLaunchAtLoginErrorPropagation()
    testLaunchAtLoginUnsupportedFallback()
    print("verify_t94a_main passed")
    exit(0)
}

RunLoop.main.run()
