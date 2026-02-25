import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

@main
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
            appState?.rotateWallpaper() ?? false
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
            loadBackgroundImageURL: { nil },
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
        #if canImport(GRDB)
        let listener = VolumeWatcher.MountListener.live(publishImportStatus: { status in
            DispatchQueue.main.async {
                appState.setImportStatus(status.message, isError: status.isError)
                appState.refreshLibraryState()
            }
        })
        #else
        let listener = VolumeWatcher.MountListener(
            importFile: { _ in
                VolumeWatcher.ImportPayload(newHighlightCount: 0, error: nil, parseWarningCount: 0)
            },
            publishImportStatus: { status in
                DispatchQueue.main.async {
                    appState.setImportStatus(status.message, isError: status.isError)
                    appState.refreshLibraryState()
                }
            }
        )
        #endif

        listener.start()
        return listener
    }

    #endif
}

#if canImport(AppKit)
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var statusItemController: StatusItemController?
    private var settingsWindowCoordinator: SettingsWindowCoordinator?
    private var hasFinishedLaunching = false

    func configure(appState: AppState) {
        self.appState = appState
        if let settingsWindowCoordinator {
            settingsWindowCoordinator.setAppState(appState)
        } else {
            settingsWindowCoordinator = SettingsWindowCoordinator(appState: appState)
        }

        if hasFinishedLaunching {
            installStatusItemIfNeeded()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hasFinishedLaunching = true
        installStatusItemIfNeeded()
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
                appState?.rotateWallpaper()
            }
        )
    }
}

private final class SettingsWindowCoordinator: NSObject, NSWindowDelegate {
    private weak var appState: AppState?
    private var settingsWindowController: NSWindowController?
    private var booksWindowController: NSWindowController?
    private var booksWindowObserver: NSObjectProtocol?

    init(appState: AppState) {
        self.appState = appState
        super.init()
        installBooksWindowObserver()
    }

    deinit {
        if let booksWindowObserver {
            NotificationCenter.default.removeObserver(booksWindowObserver)
        }
    }

    func setAppState(_ appState: AppState) {
        self.appState = appState
    }

    private func installBooksWindowObserver() {
        guard booksWindowObserver == nil else {
            return
        }

        booksWindowObserver = NotificationCenter.default.addObserver(
            forName: .kindleWallShowBooksWindow,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("[ShowBooksDebug] observer received .kindleWallShowBooksWindow")
            self?.showBooksWindow()
        }
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

        let settingsView = SettingsView()
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: settingsView)
        let window = NSWindow(contentViewController: hostingController)
        configureSettingsWindow(window)

        let controller = NSWindowController(window: window)
        settingsWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func showBooksWindow() {
        print("[ShowBooksDebug] showBooksWindow entered")
        NSApp.activate(ignoringOtherApps: true)

        if let existingWindow = booksWindowController?.window {
            print("[ShowBooksDebug] showBooksWindow branch=reuseExisting")
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }

        guard let appState else {
            print("[ShowBooksDebug] showBooksWindow branch=appStateNil")
            return
        }

        print("[ShowBooksDebug] showBooksWindow branch=createNew")
        let booksView = BooksListView()
            .environmentObject(appState)
        let hostingController = NSHostingController(rootView: booksView)
        let window = NSWindow(contentViewController: hostingController)
        configureBooksWindow(window)

        let controller = NSWindowController(window: window)
        booksWindowController = controller
        controller.showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    private func configureSettingsWindow(_ window: NSWindow) {
        window.title = "Settings"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 560))
        window.center()
        window.canHide = false
        window.hidesOnDeactivate = false
        window.delegate = self
    }

    private func configureBooksWindow(_ window: NSWindow) {
        window.title = "Books"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 560))
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
            return
        }
        if booksWindowController?.window === closedWindow {
            booksWindowController = nil
        }
    }
}

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
