#if canImport(AppKit)
import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var statusItemController: StatusItemController?
    private var settingsWindowCoordinator: SettingsWindowCoordinator?
    private var displayTopologyCoordinator: DisplayTopologyCoordinator?
    private var launchLifecycle = AppLaunchLifecycleController()

    func configure(appState: AppState) {
        self.appState = appState
        if let settingsWindowCoordinator {
            settingsWindowCoordinator.setAppState(appState)
        } else {
            settingsWindowCoordinator = SettingsWindowCoordinator(appState: appState)
        }
        if let displayTopologyCoordinator {
            displayTopologyCoordinator.setAppState(appState)
        } else {
            displayTopologyCoordinator = DisplayTopologyCoordinator(appState: appState)
        }

        _ = launchLifecycle.handleAppStateConfigured(
            appState: appState,
            installStatusItem: { [weak self] in
                self?.installStatusItemIfNeeded()
            },
            reapplyCurrentWallpaperForTopology: { configuredAppState in
                configuredAppState.reapplyCurrentWallpaperForTopologyChange()
            },
            startDisplayTopologyCoordinator: { [weak self] in
                self?.displayTopologyCoordinator?.start()
            }
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = launchLifecycle.applicationDidFinishLaunching(
            appState: appState,
            setActivationPolicy: {
                NSApp.setActivationPolicy(.accessory)
            },
            installStatusItem: { [weak self] in
                self?.installStatusItemIfNeeded()
            },
            reapplyCurrentWallpaperForTopology: { configuredAppState in
                configuredAppState.reapplyCurrentWallpaperForTopologyChange()
            },
            startDisplayTopologyCoordinator: { [weak self] in
                self?.displayTopologyCoordinator?.start()
            }
        )

        #if !TESTING
        SyncNotificationManager.shared.requestAuthorization()
        #endif
    }

    func showSettingsWindowFromCommand() {
        settingsWindowCoordinator?.showWindow()
    }

    private func installStatusItemIfNeeded() {
        guard statusItemController == nil else {
            return
        }
        guard let appState else {
            return
        }

        statusItemController = StatusItemController(
            appState: appState,
            openSettings: { [weak self] in
                self?.settingsWindowCoordinator?.showWindow()
            },
            openPreferences: { [weak self] in
                self?.settingsWindowCoordinator?.showPreferencesWindow()
            },
            rotateWallpaper: { [weak appState] in
                Task { @MainActor in
                    _ = appState?.requestWallpaperRotation()
                }
            }
        )
    }
}
#endif
