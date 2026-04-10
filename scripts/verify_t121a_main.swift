import AppKit
import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t121a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func assertFalse(_ condition: @autoclosure () -> Bool, _ message: String) {
    if condition() {
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

@MainActor
private func makeAppState() -> AppState {
    let suiteName = "verify_t121a_\(UUID().uuidString)"
    guard let userDefaults = UserDefaults(suiteName: suiteName) else {
        fail("unable to create isolated UserDefaults suite")
    }
    userDefaults.removePersistentDomain(forName: suiteName)

    return AppState(
        userDefaults: userDefaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/verify_t121a_unused.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in }
    )
}

@MainActor
private func testAppDeactivationRestoresOrderedOutSettingsWindow() {
    let probe = SettingsWindowCoordinatorTestProbe(appState: makeAppState())

    probe.showWindow()
    let controllerID = assertNotNil(
        probe.settingsWindowControllerIdentifier,
        "Expected opening Settings to create a controller"
    )
    let windowID = assertNotNil(
        probe.settingsWindowIdentifier,
        "Expected opening Settings to create a window"
    )

    probe.orderOutSettingsWindow()
    assertFalse(probe.isSettingsWindowVisible, "Expected ordered-out settings window to become hidden")

    probe.restoreWindowVisibilityAfterAppDeactivation()

    assertTrue(probe.isSettingsWindowVisible, "Expected deactivation restore to re-show the same settings window")
    assertFalse(probe.isSettingsWindowKey, "Expected restored settings window to remain a non-key background window")
    assertEqual(
        assertNotNil(
            probe.settingsWindowControllerIdentifier,
            "Expected deactivation restore to keep the existing controller"
        ),
        controllerID,
        "Expected deactivation restore to reuse the existing settings window controller"
    )
    assertEqual(
        assertNotNil(
            probe.settingsWindowIdentifier,
            "Expected deactivation restore to keep the existing window"
        ),
        windowID,
        "Expected deactivation restore to reuse the existing settings window instance"
    )
}

@MainActor
private func testRepeatedDeactivateReactivateCyclesReuseSameWindow() {
    let probe = SettingsWindowCoordinatorTestProbe(appState: makeAppState())

    probe.showWindow()
    let controllerID = assertNotNil(
        probe.settingsWindowControllerIdentifier,
        "Expected initial Settings open to create a controller"
    )
    let windowID = assertNotNil(
        probe.settingsWindowIdentifier,
        "Expected initial Settings open to create a window"
    )

    for _ in 0..<3 {
        probe.orderOutSettingsWindow()
        probe.restoreWindowVisibilityAfterAppDeactivation()

        assertTrue(probe.isSettingsWindowVisible, "Expected each deactivation cycle to keep Settings visible")
        assertEqual(
            assertNotNil(
                probe.settingsWindowControllerIdentifier,
                "Expected deactivation cycle to retain the controller"
            ),
            controllerID,
            "Expected deactivation cycle to keep the same controller instance"
        )
        assertEqual(
            assertNotNil(
                probe.settingsWindowIdentifier,
                "Expected deactivation cycle to retain the window"
            ),
            windowID,
            "Expected deactivation cycle to keep the same window instance"
        )

        probe.showWindow()

        assertEqual(
            assertNotNil(
                probe.settingsWindowControllerIdentifier,
                "Expected reopening Settings after deactivation to reuse the controller"
            ),
            controllerID,
            "Expected reopening Settings after deactivation to avoid duplicate controllers"
        )
        assertEqual(
            assertNotNil(
                probe.settingsWindowIdentifier,
                "Expected reopening Settings after deactivation to reuse the window"
            ),
            windowID,
            "Expected reopening Settings after deactivation to avoid duplicate windows"
        )
    }
}

await MainActor.run {
    testAppDeactivationRestoresOrderedOutSettingsWindow()
    testRepeatedDeactivateReactivateCyclesReuseSameWindow()
}

print("verify_t121a_main passed")
