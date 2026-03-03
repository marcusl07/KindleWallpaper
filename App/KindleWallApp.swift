import SwiftUI
#if canImport(AppKit)
import AppKit
import Combine
#endif

#if !TESTING
@main
@MainActor
struct KindleWallApp: App {
    @StateObject private var appState: AppState
    private let wallpaperScheduler: WallpaperScheduler

    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let mountListener: VolumeWatcher.MountListener?
    #endif

    init() {
        let appState = Self.makeAppState()
        _appState = StateObject(wrappedValue: appState)

        wallpaperScheduler = WallpaperScheduler(rotateWallpaper: { [weak appState] in
            guard let appState else {
                return false
            }
            return appState.requestWallpaperRotationSynchronously()
        })

        #if canImport(AppKit)
        mountListener = Self.makeMountListener(appState: appState)
        appDelegate.configure(appState: appState)
        #endif
    }

    var body: some Scene {
        Settings {
            EmptyView()
        }
        #if canImport(AppKit)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Open Settings...") {
                    appDelegate.showSettingsWindowFromCommand()
                }
                .keyboardShortcut(",", modifiers: .command)
            }
        }
        #endif
    }

    private static func makeAppState() -> AppState {
        #if canImport(GRDB)
        return AppState.live()
        #else
        return AppState(
            pickNextHighlight: { nil },
            loadBackgroundImageURLs: { [] },
            generateWallpaper: { _, _ in
                URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("kindlewall-placeholder-wallpaper.png")
            },
            setWallpaper: { _ in },
            markHighlightShown: { _ in }
        )
        #endif
    }

    #if canImport(AppKit)
    private static func makeMountListener(appState: AppState) -> VolumeWatcher.MountListener? {
        let publishImportStatusOnMain: VolumeWatcher.PublishImportStatus = { status in
            Task { @MainActor in
                appState.setImportStatus(status.message, isError: status.isError)
                appState.refreshLibraryState()
            }
        }

        #if canImport(GRDB)
        let listener = VolumeWatcher.MountListener.live(
            publishImportStatus: publishImportStatusOnMain
        )
        #else
        let listener = VolumeWatcher.MountListener(
            importFile: { _ in
                VolumeWatcher.ImportPayload(newHighlightCount: 0, error: nil, parseWarningCount: 0)
            },
            publishImportStatus: publishImportStatusOnMain
        )
        #endif

        listener.start()
        return listener
    }

    #endif
}
#endif

#if canImport(AppKit)
@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var statusItemController: StatusItemController?
    private var settingsWindowCoordinator: SettingsWindowCoordinator?
    private var didWakeObserver: NSObjectProtocol?
    private var hasFinishedLaunching = false

    deinit {
        if let didWakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(didWakeObserver)
        }
    }

    func configure(appState: AppState) {
        self.appState = appState
        if let settingsWindowCoordinator {
            settingsWindowCoordinator.setAppState(appState)
        } else {
            settingsWindowCoordinator = SettingsWindowCoordinator(appState: appState)
        }

        if hasFinishedLaunching {
            installStatusItemIfNeeded()
            installWakeObserverIfNeeded()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hasFinishedLaunching = true
        installStatusItemIfNeeded()
        installWakeObserverIfNeeded()
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
            rotateWallpaper: { [weak appState] in
                Task { @MainActor in
                    _ = appState?.requestWallpaperRotation()
                }
            }
        )
    }

    private func installWakeObserverIfNeeded() {
        guard didWakeObserver == nil else {
            return
        }

        didWakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                _ = self?.appState?.reapplyStoredWallpaperIfAvailable()
            }
        }
    }
}

@MainActor
private final class SettingsWindowCoordinator: NSObject, NSWindowDelegate, NSToolbarDelegate {
    private weak var appState: AppState?
    private var settingsWindowController: NSWindowController?
    private var settingsNavigationModel: SettingsNavigationModel?
    private var settingsNavigationObservation: AnyCancellable?
    private var backgroundsWindowController: NSWindowController?
    private var backgroundsWindowObserver: NSObjectProtocol?
    private var appDidResignActiveObserver: NSObjectProtocol?
    private weak var settingsBackToolbarItem: NSToolbarItem?
    private weak var settingsForwardToolbarItem: NSToolbarItem?

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
        restoreVisibilityIfNeeded(for: settingsWindowController?.window)
        restoreVisibilityIfNeeded(for: backgroundsWindowController?.window)
    }

    private func restoreVisibilityIfNeeded(for window: NSWindow?) {
        guard let window else {
            return
        }
        guard !window.isVisible else {
            return
        }
        guard !window.isMiniaturized else {
            return
        }

        // Keep utility windows open after focus leaves this accessory app.
        window.orderFront(nil)
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

        let navigationModel = SettingsNavigationModel()
        settingsNavigationModel = navigationModel
        let settingsView = SettingsView(navigationModel: navigationModel)
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        configureSettingsWindow(window)
        installSettingsNavigationObservation(for: navigationModel)

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

    private func configureSettingsWindow(_ window: NSWindow) {
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.setContentSize(NSSize(width: 760, height: 560))
        window.center()
        window.canHide = false
        window.hidesOnDeactivate = false
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        let toolbar = NSToolbar(identifier: "KindleWallSettingsToolbar")
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self
        window.toolbar = toolbar
        window.delegate = self
    }

    private func installSettingsNavigationObservation(for navigationModel: SettingsNavigationModel) {
        settingsNavigationObservation = navigationModel.$canGoBack
            .combineLatest(navigationModel.$canGoForward)
            .sink { [weak self] canGoBack, canGoForward in
                self?.settingsBackToolbarItem?.isEnabled = canGoBack
                self?.settingsForwardToolbarItem?.isEnabled = canGoForward
            }
    }

    @objc
    private func goBackInSettingsWindow() {
        settingsNavigationModel?.goBack()
    }

    @objc
    private func goForwardInSettingsWindow() {
        settingsNavigationModel?.goForward()
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.settingsBackNavigation, .settingsForwardNavigation]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [.settingsBackNavigation, .settingsForwardNavigation]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case .settingsBackNavigation:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Back"
            item.toolTip = "Back"
            item.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: "Back")
            item.target = self
            item.action = #selector(goBackInSettingsWindow)
            item.isBordered = true
            item.isEnabled = settingsNavigationModel?.canGoBack ?? false
            settingsBackToolbarItem = item
            return item
        case .settingsForwardNavigation:
            let item = NSToolbarItem(itemIdentifier: itemIdentifier)
            item.label = "Forward"
            item.toolTip = "Forward"
            item.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: "Forward")
            item.target = self
            item.action = #selector(goForwardInSettingsWindow)
            item.isBordered = true
            item.isEnabled = settingsNavigationModel?.canGoForward ?? false
            settingsForwardToolbarItem = item
            return item
        default:
            return nil
        }
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

    func windowWillClose(_ notification: Notification) {
        guard let closedWindow = notification.object as? NSWindow else {
            return
        }
        if settingsWindowController?.window === closedWindow {
            settingsWindowController = nil
            settingsNavigationModel = nil
            settingsNavigationObservation = nil
            settingsBackToolbarItem = nil
            settingsForwardToolbarItem = nil
            return
        }
        if backgroundsWindowController?.window === closedWindow {
            backgroundsWindowController = nil
        }
    }
}

private extension NSToolbarItem.Identifier {
    static let settingsBackNavigation = NSToolbarItem.Identifier("kindlewall.settings.back")
    static let settingsForwardNavigation = NSToolbarItem.Identifier("kindlewall.settings.forward")
}

#if TESTING
@MainActor
private extension SettingsWindowCoordinator {
    func testCloseSettingsWindow() {
        settingsWindowController?.window?.close()
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

    var testHasSettingsToolbar: Bool {
        settingsWindowController?.window?.toolbar != nil
    }

    var testSettingsToolbarItemCount: Int {
        settingsWindowController?.window?.toolbar?.items.count ?? 0
    }

    var testSettingsToolbarStyle: NSWindow.ToolbarStyle? {
        settingsWindowController?.window?.toolbarStyle
    }

    var testSettingsWindowTitleVisibility: NSWindow.TitleVisibility? {
        settingsWindowController?.window?.titleVisibility
    }

    var testSettingsWindowUsesFullSizeContentView: Bool {
        settingsWindowController?.window?.styleMask.contains(.fullSizeContentView) ?? false
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

    var settingsWindowControllerIdentifier: ObjectIdentifier? {
        coordinator.testSettingsWindowControllerIdentifier
    }

    var settingsWindowIdentifier: ObjectIdentifier? {
        coordinator.testSettingsWindowIdentifier
    }

    var isSettingsWindowVisible: Bool {
        coordinator.testIsSettingsWindowVisible
    }

    var hasSettingsToolbar: Bool {
        coordinator.testHasSettingsToolbar
    }

    var settingsToolbarItemCount: Int {
        coordinator.testSettingsToolbarItemCount
    }

    var settingsToolbarStyle: NSWindow.ToolbarStyle? {
        coordinator.testSettingsToolbarStyle
    }

    var settingsWindowTitleVisibility: NSWindow.TitleVisibility? {
        coordinator.testSettingsWindowTitleVisibility
    }

    var settingsWindowUsesFullSizeContentView: Bool {
        coordinator.testSettingsWindowUsesFullSizeContentView
    }
}

@MainActor
private func flushMainRunLoop() {
    RunLoop.main.run(until: Date().addingTimeInterval(0.05))
}
#endif

@MainActor
private final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menuBarView: MenuBarView

    init(
        appState: AppState,
        openSettings: @escaping () -> Void,
        rotateWallpaper: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.menuBarView = MenuBarView(
            appState: appState,
            nextQuoteAction: rotateWallpaper,
            openSettingsAction: openSettings,
            quitAction: {
                NSApp.terminate(nil)
            }
        )
        super.init()
        configureStatusButton()
        statusItem.menu = menuBarView.menu
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            return
        }

        if let symbol = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "KindleWall") {
            symbol.isTemplate = true
            button.image = symbol
        } else {
            button.title = "KW"
        }

        button.toolTip = "KindleWall"
    }
}
#endif
