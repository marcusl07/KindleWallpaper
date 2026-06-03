import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

#if !TESTING
@main
#endif
@MainActor
struct KindleWallApp: App {
    @StateObject private var appState: AppState
    private let wallpaperScheduler: WallpaperScheduler

    #if canImport(AppKit)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    private let mountListener: VolumeWatcher.MountListener?
    #endif

    init() {
        Self.pruneStaleWallpaperHistoryIfNeeded()

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
            SettingsView(navigationModel: SettingsNavigationModel())
                .environmentObject(appState)
        }
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

    nonisolated private static func pruneStaleWallpaperHistoryIfNeeded(
        userDefaults: UserDefaults = .standard,
        fileManager: FileManager = .default,
        indexPlistURL: URL? = nil,
        kindleWallDirectoryURL: URL? = nil
    ) {
        guard !userDefaults.didPruneStaleWallpaperHistory else {
            return
        }

        defer {
            userDefaults.didPruneStaleWallpaperHistory = true
        }

        let pruner = WallpaperHistoryPruner(
            fileManager: fileManager,
            indexPlistURL: indexPlistURL
        )
        let stalePaths = pruner.staleKindleWallPNGPaths(
            kindleWallDirectoryURL: kindleWallDirectoryURL ?? AppSupportPaths.kindleWallDirectory(fileManager: fileManager)
        )
        pruner.prune(pathsToPrune: stalePaths)
    }

    #if canImport(AppKit)
    private static func makeMountListener(appState: AppState) -> VolumeWatcher.MountListener? {
        let publishImportStatusOnMain: VolumeWatcher.PublishImportStatus = { status in
            Task { @MainActor in
                appState.setImportStatus(
                    AppState.ImportStatus(
                        message: status.message,
                        isError: status.isError,
                        warningDetails: status.warningDetails
                    )
                )
            }
        }

        #if canImport(GRDB)
        let listener = VolumeWatcher.MountListener.live(
            publishImportStatus: publishImportStatusOnMain,
            applyLibrarySnapshot: { snapshot in
                Task { @MainActor in
                    appState.applyLibrarySnapshot(snapshot)
                }
            }
        )
        #else
        let listener = VolumeWatcher.MountListener(
            importFile: { _ in
                VolumeWatcher.ImportPayload(
                    newHighlightCount: 0,
                    error: nil,
                    skippedEntryCount: 0,
                    warningMessages: []
                )
            },
            publishImportStatus: publishImportStatusOnMain
        )
        #endif

        listener.start()
        return listener
    }

    #endif
}

#if TESTING
extension KindleWallApp {
    nonisolated static func testPruneStaleWallpaperHistoryIfNeeded(
        userDefaults: UserDefaults,
        fileManager: FileManager = .default,
        indexPlistURL: URL,
        kindleWallDirectoryURL: URL
    ) {
        pruneStaleWallpaperHistoryIfNeeded(
            userDefaults: userDefaults,
            fileManager: fileManager,
            indexPlistURL: indexPlistURL,
            kindleWallDirectoryURL: kindleWallDirectoryURL
        )
    }
}
#endif
