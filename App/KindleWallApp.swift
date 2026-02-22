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
        appDelegate.configure(
            appState: appState,
            openSettings: Self.openSettingsWindow
        )
        #endif
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environmentObject(appState)
        }
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

    private static func openSettingsWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if !NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil) {
            _ = NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
        }
    }
    #endif
}

#if canImport(AppKit)
private final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var appState: AppState?
    private var openSettings: (() -> Void)?
    private var statusItemController: StatusItemController?
    private var hasFinishedLaunching = false

    func configure(appState: AppState, openSettings: @escaping () -> Void) {
        self.appState = appState
        self.openSettings = openSettings

        if hasFinishedLaunching {
            installStatusItemIfNeeded()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        hasFinishedLaunching = true
        installStatusItemIfNeeded()
    }

    private func installStatusItemIfNeeded() {
        guard statusItemController == nil else {
            return
        }
        guard let appState, let openSettings else {
            return
        }

        statusItemController = StatusItemController(
            appState: appState,
            openSettings: openSettings,
            rotateWallpaper: { [weak appState] in
                appState?.rotateWallpaper()
            }
        )
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
