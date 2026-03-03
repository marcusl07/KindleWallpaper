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

private func assertNil<T>(_ value: T?, _ message: String) {
    if value != nil {
        fail(message)
    }
}

private func assertTrue(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

@MainActor
private func testSelectionTracksDestinationUntilReset() {
    let probe = SettingsNavigationModelTestProbe()

    probe.selectRootDestination(.books)
    probe.push(.books)

    assertEqual(probe.selectedRootDestination, .books, "Expected selecting the books row to store the highlighted root row")
    assertEqual(probe.path, [.books], "Expected pushing books to preserve the existing navigation path behavior")
    assertTrue(probe.canGoBack, "Expected pushed settings navigation to enable back navigation")
    assertTrue(!probe.canGoForward, "Expected new navigation to clear any forward history")

    probe.resetRootSelection()

    assertNil(probe.selectedRootDestination, "Expected root row selection reset to clear the highlighted row")
    assertEqual(probe.path, [.books], "Expected resetting root selection to preserve navigation path state")
}

@MainActor
private func testBackForwardStateSurvivesSelectionReset() {
    let probe = SettingsNavigationModelTestProbe()

    probe.selectRootDestination(.backgrounds)
    probe.push(.backgrounds)
    probe.goBack()

    assertEqual(probe.path, [], "Expected back navigation to return to the root settings list")
    assertTrue(!probe.canGoBack, "Expected root settings list to disable back navigation")
    assertTrue(probe.canGoForward, "Expected returning to root to preserve forward navigation state")

    probe.resetRootSelection()
    assertNil(probe.selectedRootDestination, "Expected resetting selection at root to remain cleared")

    probe.goForward()

    assertEqual(probe.path, [.backgrounds], "Expected forward navigation to restore the backgrounds destination")
    assertTrue(probe.canGoBack, "Expected forward navigation to re-enable back navigation")
}

await MainActor.run {
    testSelectionTracksDestinationUntilReset()
    testBackForwardStateSurvivesSelectionReset()
}

print("verify_t68_main passed")
