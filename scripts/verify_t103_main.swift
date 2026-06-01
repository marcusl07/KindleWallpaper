import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t103_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

@main
@MainActor
enum VerifyT103 {
    static func main() {
        var mainEnabled = false
        var helperEnabled = false

        let appState = AppState(
            pickNextHighlight: { nil },
            generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
            setWallpaper: { _ in },
            markHighlightShown: { _ in },
            getLaunchAtLoginEnabled: { mainEnabled },
            refreshLaunchAtLoginEnabled: { mainEnabled },
            setLaunchAtLoginEnabled: { enabled in mainEnabled = enabled },
            getBackgroundDisplayHelperEnabled: { helperEnabled },
            refreshBackgroundDisplayHelperEnabled: { helperEnabled },
            setBackgroundDisplayHelperEnabled: { enabled in helperEnabled = enabled }
        )

        assertEqual(appState.isLaunchAtLoginEnabled, false, "Expected main login state to initialize independently")
        assertEqual(appState.isBackgroundDisplayHelperEnabled, false, "Expected helper login state to initialize independently")

        appState.setLaunchAtLoginEnabled(true)
        assertEqual(mainEnabled, true, "Expected Launch at Login toggle to update the main app service")
        assertEqual(helperEnabled, false, "Expected Launch at Login toggle not to update the helper service")

        appState.setBackgroundDisplayHelperEnabled(true)
        assertEqual(mainEnabled, true, "Expected helper toggle not to update the main app service")
        assertEqual(helperEnabled, true, "Expected helper toggle to update the DisplayHelper login item")

        mainEnabled = false
        helperEnabled = true
        appState.refreshLaunchAtLoginState()
        assertEqual(appState.isLaunchAtLoginEnabled, false, "Expected main login refresh to read the main app service")
        assertEqual(appState.isBackgroundDisplayHelperEnabled, true, "Expected helper login refresh to read the helper service")

        print("verify_t103_main passed")
    }
}
