import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t68_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail(message)
    }
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

@MainActor
private func testBackForwardStateSurvivesRootNavigation() {
    let probe = SettingsNavigationModelTestProbe()

    probe.push(.backgrounds)
    probe.goBack()

    assertEqual(probe.path, [], "Expected back navigation to return to the root settings list")
    assertTrue(!probe.canGoBack, "Expected root settings list to disable back navigation")
    assertTrue(probe.canGoForward, "Expected returning to root to preserve forward navigation state")

    probe.goForward()

    assertEqual(probe.path, [.backgrounds], "Expected forward navigation to restore the backgrounds destination")
    assertTrue(probe.canGoBack, "Expected forward navigation to re-enable back navigation")
}

await MainActor.run {
    testBackForwardStateSurvivesRootNavigation()
}

print("verify_t68_main passed")
