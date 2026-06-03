#if canImport(AppKit)
import AppKit

@MainActor
final class StatusItemController: NSObject {
    private let statusItem: NSStatusItem
    private let menuBarView: MenuBarView

    init(
        appState: AppState,
        openSettings: @escaping () -> Void,
        openPreferences: @escaping () -> Void,
        rotateWallpaper: @escaping () -> Void
    ) {
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.menuBarView = MenuBarView(
            appState: appState,
            nextQuoteAction: rotateWallpaper,
            openSettingsAction: openSettings,
            openPreferencesAction: openPreferences,
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

        if let logo = NSImage(named: "leaf-logo") {
            logo.size = NSSize(width: 16.2 * (350.0 / 550.0), height: 16.2)
            logo.isTemplate = true
            button.image = logo
        } else if let symbol = NSImage(systemSymbolName: "text.quote", accessibilityDescription: "Leaf") {
            symbol.isTemplate = true
            button.image = symbol
        } else {
            button.title = "Leaf"
        }

        button.toolTip = "Leaf"
    }
}
#endif
