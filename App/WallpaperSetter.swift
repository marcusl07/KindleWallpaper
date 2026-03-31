import AppKit
import Foundation

enum WallpaperSetter {
    enum RestoreOutcome: Equatable {
        case fullRestore
        case partialRestore
        case noStoredWallpapers
        case noConnectedScreens
        case applyFailure

        var didRestore: Bool {
            switch self {
            case .fullRestore, .partialRestore:
                return true
            case .noStoredWallpapers, .noConnectedScreens, .applyFailure:
                return false
            }
        }
    }

    struct ScreenTarget: Equatable {
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
        let backingScaleFactor: CGFloat

        init(
            identifier: String,
            pixelWidth: Int,
            pixelHeight: Int,
            backingScaleFactor: CGFloat = 1.0
        ) {
            self.identifier = identifier
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.backingScaleFactor = backingScaleFactor
        }
    }

    struct ResolvedScreen<Screen> {
        let screen: Screen
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
        let backingScaleFactor: CGFloat
        let originX: Int
        let originY: Int

        init(
            screen: Screen,
            identifier: String,
            pixelWidth: Int,
            pixelHeight: Int,
            backingScaleFactor: CGFloat = 1.0,
            originX: Int = 0,
            originY: Int = 0
        ) {
            self.screen = screen
            self.identifier = identifier
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.backingScaleFactor = backingScaleFactor
            self.originX = originX
            self.originY = originY
        }

        var target: ScreenTarget {
            ScreenTarget(
                identifier: identifier,
                pixelWidth: pixelWidth,
                pixelHeight: pixelHeight,
                backingScaleFactor: backingScaleFactor
            )
        }
    }

    struct WallpaperAssignment: Equatable {
        let screenIdentifier: String
        let imageURL: URL
    }

    static func resolvedConnectedScreens(
        screensProvider: () -> [NSScreen] = { NSScreen.screens }
    ) -> [ResolvedScreen<NSScreen>] {
        DisplayIdentityResolver.resolvedConnectedScreens(screensProvider: screensProvider)
    }

    static func connectedScreenTargets(
        screensProvider: () -> [NSScreen] = { NSScreen.screens }
    ) -> [ScreenTarget] {
        DisplayIdentityResolver.connectedScreenTargets(screensProvider: screensProvider)
    }

    static func setWallpapers(
        assignments: [WallpaperAssignment],
        on resolvedScreens: [ResolvedScreen<NSScreen>],
        setDesktopImage: (URL, NSScreen) throws -> Void = { url, screen in
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    ) {
        do {
            try trySetWallpapers(
                assignments: assignments,
                on: resolvedScreens,
                setDesktopImage: setDesktopImage
            )
        } catch {
            fatalError("Failed to set wallpaper for targeted screens: \(error)")
        }
    }

    static func setWallpapers(
        assignments: [WallpaperAssignment],
        screensProvider: () -> [NSScreen] = { NSScreen.screens },
        setDesktopImage: (URL, NSScreen) throws -> Void = { url, screen in
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    ) {
        do {
            try trySetWallpapers(
                assignments: assignments,
                on: resolvedConnectedScreens(screensProvider: screensProvider),
                setDesktopImage: setDesktopImage
            )
        } catch {
            fatalError("Failed to set wallpaper for targeted screens: \(error)")
        }
    }

    static func trySetWallpapers(
        assignments: [WallpaperAssignment],
        on resolvedScreens: [ResolvedScreen<NSScreen>],
        setDesktopImage: (URL, NSScreen) throws -> Void = { url, screen in
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    ) throws {
        try applyWallpapers(
            assignments: assignments,
            resolvedScreens: resolvedScreens,
            setDesktopImage: setDesktopImage
        )
    }

    @discardableResult
    static func restoreStoredWallpapers(
        _ wallpapers: [StoredGeneratedWallpaper],
        on resolvedScreens: [ResolvedScreen<NSScreen>],
        setDesktopImage: (URL, NSScreen) throws -> Void = { url, screen in
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    ) -> RestoreOutcome {
        restoreStoredWallpapers(
            wallpapers,
            resolvedScreens: resolvedScreens,
            setDesktopImage: setDesktopImage
        )
    }

    @discardableResult
    static func restoreStoredWallpapers<Screen>(
        _ wallpapers: [StoredGeneratedWallpaper],
        resolvedScreens: [ResolvedScreen<Screen>],
        setDesktopImage: (URL, Screen) throws -> Void
    ) -> RestoreOutcome {
        DisplayIdentityResolver.restoreStoredWallpapers(
            wallpapers,
            resolvedScreens: resolvedScreens,
            setDesktopImage: setDesktopImage
        )
    }

    @discardableResult
    static func reapplyStoredWallpapers<Screen>(
        _ wallpapers: [StoredGeneratedWallpaper],
        resolvedScreens: [ResolvedScreen<Screen>],
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows -> RestoreOutcome {
        try DisplayIdentityResolver.reapplyStoredWallpapers(
            wallpapers,
            resolvedScreens: resolvedScreens,
            setDesktopImage: setDesktopImage
        )
    }

    static func setWallpaper(
        imageURL: URL,
        screensProvider: () -> [NSScreen] = { NSScreen.screens },
        setDesktopImage: (URL, NSScreen) throws -> Void = { url, screen in
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    ) {
        do {
            try trySetWallpaper(
                imageURL: imageURL,
                screensProvider: screensProvider,
                setDesktopImage: setDesktopImage
            )
        } catch {
            fatalError("Failed to set wallpaper for all screens: \(error)")
        }
    }

    static func trySetWallpaper(
        imageURL: URL,
        screensProvider: () -> [NSScreen] = { NSScreen.screens },
        setDesktopImage: (URL, NSScreen) throws -> Void = { url, screen in
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    ) throws {
        try applyWallpaper(imageURL: imageURL, screens: screensProvider(), setDesktopImage: setDesktopImage)
    }

    @discardableResult
    static func applyWallpapers<Screen>(
        assignments: [WallpaperAssignment],
        resolvedScreens: [ResolvedScreen<Screen>],
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows -> Int {
        let urlsByIdentifier = Dictionary(
            assignments.map { assignment in
                (assignment.screenIdentifier, assignment.imageURL)
            },
            uniquingKeysWith: { _, latest in latest }
        )

        var appliedCount = 0
        for resolvedScreen in resolvedScreens {
            guard let imageURL = urlsByIdentifier[resolvedScreen.identifier] else {
                continue
            }
            try setDesktopImage(imageURL, resolvedScreen.screen)
            appliedCount += 1
        }
        return appliedCount
    }

    @discardableResult
    static func applyWallpapers<Screen>(
        assignments: [WallpaperAssignment],
        screens: [Screen],
        screenIdentifier: (Screen, Int) -> String,
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows -> Int {
        let resolvedScreens = screens.enumerated().map { index, screen in
            ResolvedScreen(
                screen: screen,
                identifier: screenIdentifier(screen, index),
                pixelWidth: 1,
                pixelHeight: 1
            )
        }
        return try applyWallpapers(
            assignments: assignments,
            resolvedScreens: resolvedScreens,
            setDesktopImage: setDesktopImage
        )
    }

    static func applyWallpaper<Screen>(
        imageURL: URL,
        screens: [Screen],
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows {
        for screen in screens {
            try setDesktopImage(imageURL, screen)
        }
    }

}

func setWallpaper(imageURL: URL) {
    WallpaperSetter.setWallpaper(imageURL: imageURL)
}
