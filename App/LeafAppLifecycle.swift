import Foundation

@MainActor
struct AppLaunchLifecycleController {
    private(set) var hasFinishedLaunching = false
    private(set) var didRunLaunchRecovery = false

    @discardableResult
    mutating func handleAppStateConfigured(
        appState: AppState?,
        installStatusItem: () -> Void,
        reapplyCurrentWallpaperForTopology: @MainActor (AppState) -> AppState.TopologyWallpaperReapplyOutcome,
        startDisplayTopologyCoordinator: () -> Void
    ) -> AppState.TopologyWallpaperReapplyOutcome? {
        guard hasFinishedLaunching else {
            return nil
        }

        return performPostLaunchWorkIfPossible(
            appState: appState,
            installStatusItem: installStatusItem,
            reapplyCurrentWallpaperForTopology: reapplyCurrentWallpaperForTopology,
            startDisplayTopologyCoordinator: startDisplayTopologyCoordinator
        )
    }

    @discardableResult
    mutating func applicationDidFinishLaunching(
        appState: AppState?,
        setActivationPolicy: () -> Void,
        installStatusItem: () -> Void,
        reapplyCurrentWallpaperForTopology: @MainActor (AppState) -> AppState.TopologyWallpaperReapplyOutcome,
        startDisplayTopologyCoordinator: () -> Void
    ) -> AppState.TopologyWallpaperReapplyOutcome? {
        setActivationPolicy()
        hasFinishedLaunching = true

        return performPostLaunchWorkIfPossible(
            appState: appState,
            installStatusItem: installStatusItem,
            reapplyCurrentWallpaperForTopology: reapplyCurrentWallpaperForTopology,
            startDisplayTopologyCoordinator: startDisplayTopologyCoordinator
        )
    }

    @discardableResult
    private mutating func performPostLaunchWorkIfPossible(
        appState: AppState?,
        installStatusItem: () -> Void,
        reapplyCurrentWallpaperForTopology: @MainActor (AppState) -> AppState.TopologyWallpaperReapplyOutcome,
        startDisplayTopologyCoordinator: () -> Void
    ) -> AppState.TopologyWallpaperReapplyOutcome? {
        installStatusItem()
        let recoveryOutcome = performLaunchRecoveryIfPossible(
            appState: appState,
            reapplyCurrentWallpaperForTopology: reapplyCurrentWallpaperForTopology
        )
        startDisplayTopologyCoordinator()
        return recoveryOutcome
    }

    @discardableResult
    private mutating func performLaunchRecoveryIfPossible(
        appState: AppState?,
        reapplyCurrentWallpaperForTopology: @MainActor (AppState) -> AppState.TopologyWallpaperReapplyOutcome
    ) -> AppState.TopologyWallpaperReapplyOutcome? {
        guard !didRunLaunchRecovery else {
            return nil
        }
        guard let appState else {
            return nil
        }

        didRunLaunchRecovery = true
        return reapplyCurrentWallpaperForTopology(appState)
    }
}

#if TESTING
@MainActor
struct AppLaunchLifecycleTestProbe {
    private var lifecycle = AppLaunchLifecycleController()
    private let setActivationPolicy: () -> Void
    private let installStatusItem: () -> Void
    private let reapplyCurrentWallpaperForTopology: @MainActor (AppState) -> AppState.TopologyWallpaperReapplyOutcome
    private let startDisplayTopologyCoordinator: () -> Void

    init(
        setActivationPolicy: @escaping () -> Void = {},
        installStatusItem: @escaping () -> Void = {},
        reapplyCurrentWallpaperForTopology: @escaping @MainActor (AppState) -> AppState.TopologyWallpaperReapplyOutcome = {
            $0.reapplyCurrentWallpaperForTopologyChange()
        },
        startDisplayTopologyCoordinator: @escaping () -> Void = {}
    ) {
        self.setActivationPolicy = setActivationPolicy
        self.installStatusItem = installStatusItem
        self.reapplyCurrentWallpaperForTopology = reapplyCurrentWallpaperForTopology
        self.startDisplayTopologyCoordinator = startDisplayTopologyCoordinator
    }

    @discardableResult
    mutating func configure(appState: AppState?) -> AppState.TopologyWallpaperReapplyOutcome? {
        lifecycle.handleAppStateConfigured(
            appState: appState,
            installStatusItem: installStatusItem,
            reapplyCurrentWallpaperForTopology: reapplyCurrentWallpaperForTopology,
            startDisplayTopologyCoordinator: startDisplayTopologyCoordinator
        )
    }

    @discardableResult
    mutating func applicationDidFinishLaunching(appState: AppState?) -> AppState.TopologyWallpaperReapplyOutcome? {
        lifecycle.applicationDidFinishLaunching(
            appState: appState,
            setActivationPolicy: setActivationPolicy,
            installStatusItem: installStatusItem,
            reapplyCurrentWallpaperForTopology: reapplyCurrentWallpaperForTopology,
            startDisplayTopologyCoordinator: startDisplayTopologyCoordinator
        )
    }

    var hasFinishedLaunching: Bool {
        lifecycle.hasFinishedLaunching
    }

    var didRunLaunchRecovery: Bool {
        lifecycle.didRunLaunchRecovery
    }
}
#endif
