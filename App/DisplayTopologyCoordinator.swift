import Foundation
#if canImport(AppKit)
import AppKit
#endif
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@MainActor
final class DisplayTopologyCoordinator {
    typealias DebouncedRestoreScheduler = @MainActor (
        _ generation: UInt64,
        _ delay: TimeInterval,
        _ operation: @escaping @MainActor (UInt64) -> Void
    ) -> Void

    nonisolated static let defaultRestoreDebounceInterval: TimeInterval = 1.0
    nonisolated static let defaultConfirmationRestoreDelay: TimeInterval = 3.0

    typealias RegisterDisplayReconfigurationCallback = @MainActor (
        _ handler: @escaping @MainActor (_ displayID: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags) -> Void
    ) -> AnyObject?
    typealias UnregisterDisplayReconfigurationCallback = @MainActor (_ registration: AnyObject) -> Void

    private weak var appState: AppState?
    private let wakeNotificationCenter: NotificationCenter
    private let wakeNotificationName: Notification.Name
    private let displayReconfigurationNotificationCenter: NotificationCenter
    private let displayReconfigurationNotificationName: Notification.Name
    private let debounceInterval: TimeInterval
    private let confirmationDelay: TimeInterval
    private let scheduleRestore: DebouncedRestoreScheduler
    private let registerDisplayReconfigurationCallback: RegisterDisplayReconfigurationCallback
    private let unregisterDisplayReconfigurationCallback: UnregisterDisplayReconfigurationCallback
    private var didWakeObserver: NSObjectProtocol?
    private var displayReconfigurationObserver: NSObjectProtocol?
    private var displayCallbackRegistration: AnyObject?
    private var restoreGeneration: UInt64 = 0

    init(
        appState: AppState? = nil,
        notificationCenter: NotificationCenter,
        wakeNotificationName: Notification.Name,
        displayReconfigurationNotificationCenter: NotificationCenter,
        displayReconfigurationNotificationName: Notification.Name,
        debounceInterval: TimeInterval = DisplayTopologyCoordinator.defaultRestoreDebounceInterval,
        confirmationDelay: TimeInterval = DisplayTopologyCoordinator.defaultConfirmationRestoreDelay,
        registerDisplayReconfigurationCallback: @escaping RegisterDisplayReconfigurationCallback = DisplayTopologyCoordinator.registerDisplayReconfigurationCallback,
        unregisterDisplayReconfigurationCallback: @escaping UnregisterDisplayReconfigurationCallback = DisplayTopologyCoordinator.unregisterDisplayReconfigurationCallback,
        scheduleRestore: @escaping DebouncedRestoreScheduler = DisplayTopologyCoordinator.scheduleRestore
    ) {
        self.appState = appState
        self.wakeNotificationCenter = notificationCenter
        self.wakeNotificationName = wakeNotificationName
        self.displayReconfigurationNotificationCenter = displayReconfigurationNotificationCenter
        self.displayReconfigurationNotificationName = displayReconfigurationNotificationName
        self.debounceInterval = debounceInterval
        self.confirmationDelay = confirmationDelay
        self.registerDisplayReconfigurationCallback = registerDisplayReconfigurationCallback
        self.unregisterDisplayReconfigurationCallback = unregisterDisplayReconfigurationCallback
        self.scheduleRestore = scheduleRestore
    }

    #if canImport(AppKit)
    convenience init(
        appState: AppState? = nil,
        debounceInterval: TimeInterval = DisplayTopologyCoordinator.defaultRestoreDebounceInterval,
        confirmationDelay: TimeInterval = DisplayTopologyCoordinator.defaultConfirmationRestoreDelay
    ) {
        self.init(
            appState: appState,
            notificationCenter: NSWorkspace.shared.notificationCenter,
            wakeNotificationName: NSWorkspace.didWakeNotification,
            displayReconfigurationNotificationCenter: .default,
            displayReconfigurationNotificationName: NSApplication.didChangeScreenParametersNotification,
            debounceInterval: debounceInterval,
            confirmationDelay: confirmationDelay
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
        guard didWakeObserver == nil, displayReconfigurationObserver == nil, displayCallbackRegistration == nil else {
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

        displayCallbackRegistration = registerDisplayReconfigurationCallback { [weak self] _, flags in
            self?.handleCoreGraphicsDisplayReconfiguration(flags: flags)
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

        if let displayCallbackRegistration {
            unregisterDisplayReconfigurationCallback(displayCallbackRegistration)
            self.displayCallbackRegistration = nil
        }

        invalidatePendingRestore()
    }

    func handleWakeNotification() {
        scheduleRestorePass()
    }

    func handleDisplayReconfigurationNotification() {
        scheduleRestorePass()
    }

    func handleCoreGraphicsDisplayReconfiguration(
        flags: CGDisplayChangeSummaryFlags
    ) {
        guard !flags.contains(.beginConfigurationFlag) else {
            return
        }

        scheduleRestorePass()
    }

    private func scheduleRestorePass() {
        restoreGeneration &+= 1
        let generation = restoreGeneration
        scheduleRestore(generation, debounceInterval) { [weak self] scheduledGeneration in
            guard let self, self.restoreGeneration == scheduledGeneration else {
                return
            }

            self.appState?.reapplyCurrentWallpaperForTopologyChange()
        }
        scheduleRestore(generation, confirmationDelay) { [weak self] scheduledGeneration in
            guard let self, self.restoreGeneration == scheduledGeneration else {
                return
            }

            self.appState?.reapplyCurrentWallpaperForTopologyChange()
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

    nonisolated private static func registerDisplayReconfigurationCallback(
        _ handler: @escaping @MainActor (_ displayID: CGDirectDisplayID, _ flags: CGDisplayChangeSummaryFlags) -> Void
    ) -> AnyObject? {
        let registration = CoreGraphicsDisplayCallbackRegistration(handler: handler)
        let userInfo = Unmanaged.passUnretained(registration).toOpaque()
        let error = CGDisplayRegisterReconfigurationCallback(
            coreGraphicsDisplayReconfigurationCallback,
            userInfo
        )
        guard error == .success else {
            return nil
        }

        return registration
    }

    nonisolated private static func unregisterDisplayReconfigurationCallback(
        _ registration: AnyObject
    ) {
        guard let registration = registration as? CoreGraphicsDisplayCallbackRegistration else {
            return
        }

        let userInfo = Unmanaged.passUnretained(registration).toOpaque()
        CGDisplayRemoveReconfigurationCallback(
            coreGraphicsDisplayReconfigurationCallback,
            userInfo
        )
    }

    nonisolated private static let coreGraphicsDisplayReconfigurationCallback: CGDisplayReconfigurationCallBack = {
        displayID,
        flags,
        userInfo
        in
        guard let userInfo else {
            return
        }

        let registration = Unmanaged<CoreGraphicsDisplayCallbackRegistration>
            .fromOpaque(userInfo)
            .takeUnretainedValue()

        if Thread.isMainThread {
            MainActor.assumeIsolated {
                registration.handler(displayID, flags)
            }
        } else {
            Task { @MainActor in
                registration.handler(displayID, flags)
            }
        }
    }
}

private final class CoreGraphicsDisplayCallbackRegistration: NSObject {
    let handler: @MainActor (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void

    init(
        handler: @escaping @MainActor (CGDirectDisplayID, CGDisplayChangeSummaryFlags) -> Void
    ) {
        self.handler = handler
    }
}
