import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t61_main failed: \(message)\n", stderr)
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

@MainActor
private func makeUserDefaults(prefix: String) -> UserDefaults {
    let suiteName = "\(prefix)-\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        fail("Unable to create isolated UserDefaults suite")
    }
    userDefaults.removePersistentDomain(forName: suiteName)
    userDefaults.set(suiteName, forKey: "__verifySuiteName")
    return userDefaults
}

private func clearUserDefaults(_ userDefaults: UserDefaults) {
    guard let suiteName = userDefaults.string(forKey: "__verifySuiteName"), !suiteName.isEmpty else {
        return
    }

    userDefaults.removePersistentDomain(forName: suiteName)
}

@MainActor
private func makeAppState(
    userDefaults: UserDefaults,
    reapplyStoredWallpaper: @escaping AppState.ReapplyStoredWallpaper = { .noStoredWallpapers },
    reapplyCurrentWallpaperForTopology: @escaping AppState.ReapplyCurrentWallpaperForTopology = { .noCurrentWallpaper }
) -> AppState {
    AppState(
        userDefaults: userDefaults,
        pickNextHighlight: { nil },
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/verify_t61_unused.png")
        },
        setWallpaper: { _ in },
        reapplyStoredWallpaper: reapplyStoredWallpaper,
        reapplyCurrentWallpaperForTopology: reapplyCurrentWallpaperForTopology,
        markHighlightShown: { _ in },
        getLaunchAtLoginEnabled: { false },
        refreshLaunchAtLoginEnabled: { false }
    )
}

@MainActor
private func testLaunchRecoveryRunsOnceOnStartupAndUsesTopologyAwarePath() {
    let userDefaults = makeUserDefaults(prefix: "verify-t61-startup")
    defer { clearUserDefaults(userDefaults) }

    var storedReapplyCallCount = 0
    var topologyReapplyCallCount = 0
    var events: [String] = []

    let appState = makeAppState(
        userDefaults: userDefaults,
        reapplyStoredWallpaper: {
            storedReapplyCallCount += 1
            return .fullRestore
        },
        reapplyCurrentWallpaperForTopology: {
            topologyReapplyCallCount += 1
            events.append("recover")
            return .reapplied
        }
    )

    var probe = AppLaunchLifecycleTestProbe(
        setActivationPolicy: {
            events.append("policy")
        },
        installStatusItem: {
            events.append("install")
        },
        startDisplayTopologyCoordinator: {
            events.append("start")
        }
    )

    let prelaunchResult = probe.configure(appState: appState)
    expectEqual(prelaunchResult, nil, "Expected configure before launch completion not to recover")
    expectEqual(events, [], "Expected prelaunch configure not to run launch actions")

    let launchResult = probe.applicationDidFinishLaunching(appState: appState)

    expectEqual(launchResult, .reapplied, "Expected launch recovery to forward the topology reapply outcome")
    expect(probe.hasFinishedLaunching, "Expected launch lifecycle to record startup completion")
    expect(probe.didRunLaunchRecovery, "Expected launch recovery to be marked as complete")
    expectEqual(storedReapplyCallCount, 0, "Expected startup recovery not to use the legacy stored-wallpaper path")
    expectEqual(topologyReapplyCallCount, 1, "Expected startup recovery to invoke topology reapply exactly once")
    expectEqual(events, ["policy", "install", "recover", "start"], "Expected coordinator startup to happen after launch recovery")

    let reconfigureResult = probe.configure(appState: appState)
    expectEqual(reconfigureResult, nil, "Expected configure after startup not to re-run launch recovery")
    expectEqual(topologyReapplyCallCount, 1, "Expected launch recovery to stay one-shot per app launch")
}

@MainActor
private func testLaunchRecoveryWaitsForInjectedAppStateAndStillRunsOnce() {
    var topologyReapplyCallCount = 0
    var events: [String] = []

    var probe = AppLaunchLifecycleTestProbe(
        setActivationPolicy: {
            events.append("policy")
        },
        installStatusItem: {
            events.append("install")
        },
        startDisplayTopologyCoordinator: {
            events.append("start")
        }
    )

    let initialResult = probe.applicationDidFinishLaunching(appState: nil)
    expectEqual(initialResult, nil, "Expected launch recovery to no-op until AppState is configured")
    expect(probe.hasFinishedLaunching, "Expected launch completion state to persist without AppState")
    expect(!probe.didRunLaunchRecovery, "Expected launch recovery to remain pending without AppState")

    let userDefaults = makeUserDefaults(prefix: "verify-t61-late-app-state")
    defer { clearUserDefaults(userDefaults) }

    let appState = makeAppState(
        userDefaults: userDefaults,
        reapplyCurrentWallpaperForTopology: {
            topologyReapplyCallCount += 1
            events.append("recover")
            return .alreadyApplied
        }
    )

    let configureResult = probe.configure(appState: appState)
    expectEqual(configureResult, .alreadyApplied, "Expected post-launch configure to run the pending recovery once")
    expect(probe.didRunLaunchRecovery, "Expected pending launch recovery to complete after AppState injection")
    expectEqual(topologyReapplyCallCount, 1, "Expected delayed startup recovery to run exactly once")
    expectEqual(events, ["policy", "install", "start", "install", "recover", "start"], "Expected recovery to run before the post-configure coordinator start")

    let secondConfigureResult = probe.configure(appState: appState)
    expectEqual(secondConfigureResult, nil, "Expected subsequent configure calls not to re-run launch recovery")
    expectEqual(topologyReapplyCallCount, 1, "Expected delayed launch recovery to remain one-shot")
}

@MainActor
private func testLaunchRecoveryRunsAcrossScheduleModesWithoutLaunchAtLogin() {
    let modes: [RotationScheduleMode] = [.manual, .daily, .everyInterval, .onLaunch]

    for mode in modes {
        let userDefaults = makeUserDefaults(prefix: "verify-t61-mode-\(mode.rawValue)")
        defer { clearUserDefaults(userDefaults) }

        userDefaults.rotationScheduleMode = mode

        var topologyReapplyCallCount = 0
        let appState = makeAppState(
            userDefaults: userDefaults,
            reapplyCurrentWallpaperForTopology: {
                topologyReapplyCallCount += 1
                return .reapplied
            }
        )

        var probe = AppLaunchLifecycleTestProbe()
        let result = probe.applicationDidFinishLaunching(appState: appState)

        expectEqual(result, .reapplied, "Expected launch recovery to run in \(mode.rawValue) mode")
        expectEqual(topologyReapplyCallCount, 1, "Expected launch recovery to ignore schedule mode in \(mode.rawValue) mode")
        expect(!appState.isLaunchAtLoginEnabled, "Expected launch-at-login to remain disabled in verification setup")
    }
}

@MainActor
private func testLaunchRecoveryForwardsStructuredOutcomes() {
    let outcomes: [AppState.TopologyWallpaperReapplyOutcome] = [
        .alreadyApplied,
        .noCurrentWallpaper,
        .noConnectedScreens,
        .applyFailure
    ]

    for outcome in outcomes {
        let userDefaults = makeUserDefaults(prefix: "verify-t61-outcome-\(String(describing: outcome))")
        defer { clearUserDefaults(userDefaults) }

        let appState = makeAppState(
            userDefaults: userDefaults,
            reapplyCurrentWallpaperForTopology: {
                outcome
            }
        )

        var probe = AppLaunchLifecycleTestProbe()
        let result = probe.applicationDidFinishLaunching(appState: appState)

        expectEqual(result, outcome, "Expected launch recovery to forward \(outcome) without crashing startup")
    }
}

await MainActor.run {
    testLaunchRecoveryRunsOnceOnStartupAndUsesTopologyAwarePath()
    testLaunchRecoveryWaitsForInjectedAppStateAndStillRunsOnce()
    testLaunchRecoveryRunsAcrossScheduleModesWithoutLaunchAtLogin()
    testLaunchRecoveryForwardsStructuredOutcomes()
}

print("verify_t61_main passed")
