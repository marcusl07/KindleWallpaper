import AppKit
import Foundation

@main
@MainActor
enum DisplayHelperApp {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let runtime = DisplayHelperRuntime()
        runtime.start()
        NSApplication.shared.run()
    }
}

@MainActor
final class DisplayHelperRuntime {
    private var displayTopologyCoordinator: DisplayTopologyCoordinator?

    func start() {
        attemptMigration()
        _ = makeRestorer().reapply()
        let coordinator = DisplayTopologyCoordinator(
            restoreAction: { [weak self] in
                guard let self else {
                    return .noCurrentWallpaper
                }
                return self.makeRestorer().reapply()
            }
        )
        displayTopologyCoordinator = coordinator
        coordinator.start()
    }

    private func attemptMigration() {
        guard
            let appGroupDefaults = KindleWallSharedStorage.appGroupUserDefaults(),
            let generatedWallpapersDirectoryURL = KindleWallSharedStorage.generatedWallpapersContainerURL()
        else {
            return
        }

        _ = try? UserDefaults.standard.migrateWallpaperAssignmentsToAppGroupIfNeeded(
            appGroupDefaults: appGroupDefaults,
            appGroupGeneratedWallpapersDirectoryURL: generatedWallpapersDirectoryURL
        )
    }

    private func makeRestorer() -> WallpaperTopologyRestorer<NSScreen> {
        let sharedDefaults = KindleWallSharedStorage.appGroupUserDefaults() ?? .standard
        return WallpaperTopologyRestorer(
            loadStoredWallpapers: {
                sharedDefaults.loadReusableGeneratedWallpapers()
            },
            resolvedScreens: {
                DisplayIdentityResolver.resolvedConnectedScreens()
            },
            preferredSourceScreen: {
                nil
            },
            sameScreen: { lhs, rhs in
                lhs === rhs
            },
            currentDesktopImageURL: { screen in
                NSWorkspace.shared.desktopImageURL(for: screen)
            },
            setDesktopImage: { url, screen in
                try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
            }
        )
    }
}
