#if canImport(AppKit)
import AppKit
import SwiftUI

@MainActor
final class SettingsWindowCoordinator: NSObject, NSWindowDelegate {
    private weak var appState: AppState?
    private var settingsWindowController: NSWindowController?
    private var preferencesWindowController: NSWindowController?
    private var backgroundsWindowController: NSWindowController?
    private var backgroundsWindowObserver: NSObjectProtocol?
    private var appDidResignActiveObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        installBackgroundsWindowObserver()
        installAppDeactivationObserver()
    }

    deinit {
        if let backgroundsWindowObserver {
            NotificationCenter.default.removeObserver(backgroundsWindowObserver)
        }
        if let appDidResignActiveObserver {
            NotificationCenter.default.removeObserver(appDidResignActiveObserver)
        }
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    private func installBackgroundsWindowObserver() {
        guard backgroundsWindowObserver == nil else {
            return
        }

        backgroundsWindowObserver = NotificationCenter.default.addObserver(
            forName: .kindleWallShowBackgroundsWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.showBackgroundsWindow()
            }
        }
    }

    private func installAppDeactivationObserver() {
        guard appDidResignActiveObserver == nil else {
            return
        }

        appDidResignActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.restoreWindowVisibilityAfterAppDeactivation()
            }
        }
    }

    private func restoreWindowVisibilityAfterAppDeactivation() {
        restoreVisibilityIfNeeded(for: settingsWindowController)
        restoreVisibilityIfNeeded(for: backgroundsWindowController)
        restoreVisibilityIfNeeded(for: preferencesWindowController)
    }

    private func restoreVisibilityIfNeeded(for windowController: NSWindowController?) {
        guard let windowController, let window = windowController.window else {
            return
        }
        guard !window.isVisible else {
            return
        }
        guard !window.isMiniaturized else {
            return
        }

        // Keep utility windows open after focus leaves this accessory app.
        windowController.showWindow(nil)
        window.orderFrontRegardless()
    }

    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let existingWindow = settingsWindowController?.window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        guard let appState else {
            return
        }

        let libraryView = LibraryView()
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: libraryView)
        let window = NSWindow(contentViewController: hostingController)
        configureSettingsWindow(window)

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func showBackgroundsWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let existingWindow = backgroundsWindowController?.window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        guard let appState else {
            return
        }

        let backgroundsView = BackgroundsListView()
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: backgroundsView)
        let window = NSWindow(contentViewController: hostingController)
        configureBackgroundsWindow(window)

        let controller = NSWindowController(window: window)
        backgroundsWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    func showPreferencesWindow() {
        NSApp.activate(ignoringOtherApps: true)

        if let existingWindow = preferencesWindowController?.window {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        guard let appState else {
            return
        }

        let preferencesView = SettingsView(navigationModel: SettingsNavigationModel())
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: preferencesView)
        let window = NSWindow(contentViewController: hostingController)
        configurePreferencesWindow(window)

        let controller = NSWindowController(window: window)
        preferencesWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.title = "Library"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1240, height: 650))
        window.minSize = NSSize(width: 1120, height: 600)
        window.center()
        window.canHide = false
        window.hidesOnDeactivate = false
        window.titleVisibility = .visible
        window.toolbarStyle = .unified
        window.delegate = self
    }

    private func configurePreferencesWindow(_ window: NSWindow) {
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.setContentSize(NSSize(width: 480, height: 380))
        window.center()
        window.canHide = false
        window.hidesOnDeactivate = false
        window.delegate = self
    }

    private func configureBackgroundsWindow(_ window: NSWindow) {
        window.title = "Backgrounds"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 860, height: 620))
        window.center()
        window.canHide = false
        window.hidesOnDeactivate = false
        window.delegate = self
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        cleanupController(for: sender)
        return true
    }

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else {
            return
        }
        cleanupController(for: closedWindow)
    }

    private func cleanupController(for window: NSWindow) {
        if settingsWindowController?.window === window {
            settingsWindowController = nil
        } else if preferencesWindowController?.window === window {
            preferencesWindowController = nil
        } else if backgroundsWindowController?.window === window {
            backgroundsWindowController = nil
        }
    }
}

#if TESTING
@MainActor
private extension SettingsWindowCoordinator {
    func testCloseSettingsWindow() {
        settingsWindowController?.window?.close()
    }

    func testRestoreWindowVisibilityAfterAppDeactivation() {
        restoreWindowVisibilityAfterAppDeactivation()
    }

    func testOrderOutSettingsWindow() {
        settingsWindowController?.window?.orderOut(nil)
    }

    var testSettingsWindowControllerIdentifier: ObjectIdentifier? {
        settingsWindowController.map(ObjectIdentifier.init)
    }

    var testSettingsWindowIdentifier: ObjectIdentifier? {
        settingsWindowController?.window.map(ObjectIdentifier.init)
    }

    var testIsSettingsWindowVisible: Bool {
        settingsWindowController?.window?.isVisible ?? false
    }

    var testIsSettingsWindowKey: Bool {
        settingsWindowController?.window?.isKeyWindow ?? false
    }

    var testSettingsToolbarStyle: NSWindow.ToolbarStyle? {
        settingsWindowController?.window?.toolbarStyle
    }

    var testSettingsWindowTitleVisibility: NSWindow.TitleVisibility? {
        settingsWindowController?.window?.titleVisibility
    }

    var testSettingsWindowTitlebarAppearsTransparent: Bool {
        settingsWindowController?.window?.titlebarAppearsTransparent ?? false
    }
}

@MainActor
struct SettingsWindowCoordinatorTestProbe {
    private let retainedAppState: AppState
    private let coordinator: SettingsWindowCoordinator

    init(appState: AppState) {
        _ = NSApplication.shared
        retainedAppState = appState
        coordinator = SettingsWindowCoordinator(appState: appState)
    }

    func showWindow() {
        coordinator.showWindow()
        flushMainRunLoop()
    }

    func closeSettingsWindow() {
        coordinator.testCloseSettingsWindow()
        flushMainRunLoop()
    }

    func simulateAppDeactivation() {
        NotificationCenter.default.post(
            name: NSApplication.didResignActiveNotification,
            object: NSApp
        )
        flushMainRunLoop()
    }

    func orderOutSettingsWindow() {
        coordinator.testOrderOutSettingsWindow()
        flushMainRunLoop()
    }

    func restoreWindowVisibilityAfterAppDeactivation() {
        coordinator.testRestoreWindowVisibilityAfterAppDeactivation()
        flushMainRunLoop()
    }

    var settingsWindowControllerIdentifier: ObjectIdentifier? {
        coordinator.testSettingsWindowControllerIdentifier
    }

    var settingsWindowIdentifier: ObjectIdentifier? {
        coordinator.testSettingsWindowIdentifier
    }

    var isSettingsWindowVisible: Bool {
        coordinator.testIsSettingsWindowVisible
    }

    var isSettingsWindowKey: Bool {
        coordinator.testIsSettingsWindowKey
    }

    var settingsToolbarStyle: NSWindow.ToolbarStyle? {
        coordinator.testSettingsToolbarStyle
    }

    var settingsWindowTitleVisibility: NSWindow.TitleVisibility? {
        coordinator.testSettingsWindowTitleVisibility
    }

    var settingsWindowTitlebarAppearsTransparent: Bool {
        coordinator.testSettingsWindowTitlebarAppearsTransparent
    }
}

@MainActor
private func flushMainRunLoop() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
#endif
#endif
