import Foundation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class DisplayTopologyCoordinator {
    private weak var appState: AppState?
    private let notificationCenter: NotificationCenter
    private let wakeNotificationName: Notification.Name
    private var didWakeObserver: NSObjectProtocol?

    init(
        appState: AppState? = nil,
        notificationCenter: NotificationCenter,
        wakeNotificationName: Notification.Name
    ) {
        self.appState = appState
        self.notificationCenter = notificationCenter
        self.wakeNotificationName = wakeNotificationName
    }

    #if canImport(AppKit)
    convenience init(appState: AppState? = nil) {
        self.init(
            appState: appState,
            notificationCenter: NSWorkspace.shared.notificationCenter,
            wakeNotificationName: NSWorkspace.didWakeNotification
        )
    }
    #endif

    deinit {
        MainActor.assumeIsolated {
            stop()
        }
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    func start() {
        guard didWakeObserver == nil else {
            return
        }

        didWakeObserver = notificationCenter.addObserver(
            forName: wakeNotificationName,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else {
                return
            }

            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    _ = self.handleWakeNotification()
                }
            } else {
                Task { @MainActor [weak self] in
                    _ = self?.handleWakeNotification()
                }
            }
        }
    }

    func stop() {
        guard let didWakeObserver else {
            return
        }

        notificationCenter.removeObserver(didWakeObserver)
        self.didWakeObserver = nil
    }

    @discardableResult
    func handleWakeNotification() -> WallpaperSetter.RestoreOutcome? {
        appState?.reapplyStoredWallpaperIfAvailable()
    }
}
