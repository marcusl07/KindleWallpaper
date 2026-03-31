import Foundation
#if canImport(AppKit)
import AppKit
#endif

@MainActor
final class DisplayTopologyCoordinator {
    typealias DebouncedRestoreScheduler = @MainActor (
        _ generation: UInt64,
        _ delay: TimeInterval,
        _ operation: @escaping @MainActor (UInt64) -> Void
    ) -> Void

    nonisolated static let defaultRestoreDebounceInterval: TimeInterval = 1.0

    private weak var appState: AppState?
    private let wakeNotificationCenter: NotificationCenter
    private let wakeNotificationName: Notification.Name
    private let displayReconfigurationNotificationCenter: NotificationCenter
    private let displayReconfigurationNotificationName: Notification.Name
    private let debounceInterval: TimeInterval
    private let scheduleRestore: DebouncedRestoreScheduler
    private var didWakeObserver: NSObjectProtocol?
    private var displayReconfigurationObserver: NSObjectProtocol?
    private var restoreGeneration: UInt64 = 0

    init(
        appState: AppState? = nil,
        notificationCenter: NotificationCenter,
        wakeNotificationName: Notification.Name,
        displayReconfigurationNotificationCenter: NotificationCenter,
        displayReconfigurationNotificationName: Notification.Name,
        debounceInterval: TimeInterval = DisplayTopologyCoordinator.defaultRestoreDebounceInterval,
        scheduleRestore: @escaping DebouncedRestoreScheduler = DisplayTopologyCoordinator.scheduleRestore
    ) {
        self.appState = appState
        self.wakeNotificationCenter = notificationCenter
        self.wakeNotificationName = wakeNotificationName
        self.displayReconfigurationNotificationCenter = displayReconfigurationNotificationCenter
        self.displayReconfigurationNotificationName = displayReconfigurationNotificationName
        self.debounceInterval = debounceInterval
        self.scheduleRestore = scheduleRestore
    }

    #if canImport(AppKit)
    convenience init(
        appState: AppState? = nil,
        debounceInterval: TimeInterval = DisplayTopologyCoordinator.defaultRestoreDebounceInterval
    ) {
        self.init(
            appState: appState,
            notificationCenter: NSWorkspace.shared.notificationCenter,
            wakeNotificationName: NSWorkspace.didWakeNotification,
            displayReconfigurationNotificationCenter: .default,
            displayReconfigurationNotificationName: NSApplication.didChangeScreenParametersNotification,
            debounceInterval: debounceInterval
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
        guard didWakeObserver == nil, displayReconfigurationObserver == nil else {
            return
        }

        didWakeObserver = wakeNotificationCenter.addObserver(
            forName: wakeNotificationName,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else {
                return
            }

            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.handleWakeNotification()
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleWakeNotification()
                }
            }
        }

        displayReconfigurationObserver = displayReconfigurationNotificationCenter.addObserver(
            forName: displayReconfigurationNotificationName,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            guard let self else {
                return
            }

            if Thread.isMainThread {
                MainActor.assumeIsolated {
                    self.handleDisplayReconfigurationNotification()
                }
            } else {
                Task { @MainActor [weak self] in
                    self?.handleDisplayReconfigurationNotification()
                }
            }
        }
    }

    func stop() {
        if let didWakeObserver {
            wakeNotificationCenter.removeObserver(didWakeObserver)
            self.didWakeObserver = nil
        }

        if let displayReconfigurationObserver {
            displayReconfigurationNotificationCenter.removeObserver(displayReconfigurationObserver)
            self.displayReconfigurationObserver = nil
        }

        invalidatePendingRestore()
    }

    func handleWakeNotification() {
        scheduleRestorePass()
    }

    func handleDisplayReconfigurationNotification() {
        scheduleRestorePass()
    }

    private func scheduleRestorePass() {
        restoreGeneration &+= 1
        let generation = restoreGeneration
        scheduleRestore(generation, debounceInterval) { [weak self] scheduledGeneration in
            guard let self, self.restoreGeneration == scheduledGeneration else {
                return
            }

            self.appState?.reapplyStoredWallpaperIfAvailable()
        }
    }

    private func invalidatePendingRestore() {
        restoreGeneration &+= 1
    }

    nonisolated private static func scheduleRestore(
        generation: UInt64,
        delay: TimeInterval,
        operation: @escaping @MainActor (UInt64) -> Void
    ) {
        let delayNanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
        Task {
            if delayNanoseconds > 0 {
                try? await Task.sleep(nanoseconds: delayNanoseconds)
            }
            await MainActor.run {
                operation(generation)
            }
        }
    }
}
