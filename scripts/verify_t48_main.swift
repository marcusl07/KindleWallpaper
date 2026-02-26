import AppKit
import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t48_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func assertNil<T>(_ value: T?, _ message: String) {
    if value != nil {
        fail(message)
    }
}

private func assertNotNil<T>(_ value: T?, _ message: String) -> T {
    guard let value else {
        fail(message)
    }
    return value
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail(message)
    }
}

private func assertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs == rhs {
        fail(message)
    }
}

@MainActor
private func makeAppState() -> AppState {
    let suiteName = "verify_t48_\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        fail("unable to create isolated UserDefaults suite")
    }
    userDefaults.removePersistentDomain(forName: suiteName)

    return AppState(
        userDefaults: userDefaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/verify_t48_unused.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )
}

@MainActor
private func testFreshOpenCreatesVisibleWindow() {
    let probe = SettingsWindowCoordinatorTestProbe(appState: makeAppState())

    probe.showWindow()

    assertTrue(probe.isSettingsWindowVisible, "Expected fresh settings open to produce a visible window")
    _ = assertNotNil(probe.settingsWindowControllerIdentifier, "Expected fresh settings open to create a window controller")
    _ = assertNotNil(probe.settingsWindowIdentifier, "Expected fresh settings open to create a window instance")
}

@MainActor
private func testSecondOpenReusesSameWindowInstance() {
    let probe = SettingsWindowCoordinatorTestProbe(appState: makeAppState())

    probe.showWindow()
    let firstControllerID = assertNotNil(
        probe.settingsWindowControllerIdentifier,
        "Expected first settings open to create a controller"
    )
    let firstWindowID = assertNotNil(
        probe.settingsWindowIdentifier,
        "Expected first settings open to create a window"
    )

    probe.showWindow()

    let secondControllerID = assertNotNil(
        probe.settingsWindowControllerIdentifier,
        "Expected second settings open to keep a controller"
    )
    let secondWindowID = assertNotNil(
        probe.settingsWindowIdentifier,
        "Expected second settings open to keep a window"
    )

    assertEqual(secondControllerID, firstControllerID, "Expected second settings open to reuse controller instance")
    assertEqual(secondWindowID, firstWindowID, "Expected second settings open to reuse window instance")
}

@MainActor
private func testCloseNilsControllerSoNextOpenRecreates() {
    let probe = SettingsWindowCoordinatorTestProbe(appState: makeAppState())

    probe.showWindow()
    let firstControllerID = assertNotNil(
        probe.settingsWindowControllerIdentifier,
        "Expected initial settings open to create controller"
    )

    probe.closeSettingsWindow()
    assertNil(
        probe.settingsWindowControllerIdentifier,
        "Expected closing settings window to clear retained controller"
    )

    probe.showWindow()
    let recreatedControllerID = assertNotNil(
        probe.settingsWindowControllerIdentifier,
        "Expected opening after close to create replacement controller"
    )

    assertNotEqual(
        recreatedControllerID,
        firstControllerID,
        "Expected reopening after close to create a new controller instance"
    )
}

@MainActor
private func testAppDeactivationRestoresSettingsWindowVisibility() {
    let probe = SettingsWindowCoordinatorTestProbe(appState: makeAppState())

    probe.showWindow()
    assertTrue(probe.isSettingsWindowVisible, "Expected settings window to start visible before deactivation")
    let initialWindowID = assertNotNil(
        probe.settingsWindowIdentifier,
        "Expected settings window to have an identifier before deactivation"
    )

    probe.simulateAppDeactivation()
    assertTrue(probe.isSettingsWindowVisible, "Expected app deactivation handling to keep settings window visible")
    assertEqual(
        assertNotNil(probe.settingsWindowIdentifier, "Expected settings window to remain allocated after deactivation"),
        initialWindowID,
        "Expected deactivation handling to keep the same settings window instance"
    )
}

await MainActor.run {
    testFreshOpenCreatesVisibleWindow()
    testSecondOpenReusesSameWindowInstance()
    testCloseNilsControllerSoNextOpenRecreates()
    testAppDeactivationRestoresSettingsWindowVisibility()
}

print("verify_t48_main passed")
