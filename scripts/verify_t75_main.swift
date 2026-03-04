import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t75_main failed: \(message)\n", stderr)
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
private func testQuotesDestinationSupportsBackForwardNavigation() {
    let probe = SettingsNavigationModelTestProbe()

    probe.push(.quotes)
    assertEqual(probe.path, [.quotes], "Expected quotes destination to push onto the settings path")
    assertTrue(probe.canGoBack, "Expected quotes destination to enable back navigation")

    probe.goBack()
    assertEqual(probe.path, [], "Expected going back from quotes to return to the root settings list")
    assertTrue(!probe.canGoBack, "Expected root settings list to disable back navigation after leaving quotes")
    assertTrue(probe.canGoForward, "Expected quotes destination to remain available for forward navigation")

    probe.goForward()
    assertEqual(probe.path, [.quotes], "Expected forward navigation to restore the quotes destination")
}

await MainActor.run {
    testQuotesDestinationSupportsBackForwardNavigation()
}

print("verify_t75_main passed")
