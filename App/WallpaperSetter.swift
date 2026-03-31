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

        init(
            screen: Screen,
            identifier: String,
            pixelWidth: Int,
            pixelHeight: Int,
            backingScaleFactor: CGFloat = 1.0
        ) {
            self.screen = screen
            self.identifier = identifier
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.backingScaleFactor = backingScaleFactor
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

    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    static func resolvedConnectedScreens(
        screensProvider: () -> [NSScreen] = { NSScreen.screens }
    ) -> [ResolvedScreen<NSScreen>] {
        screensProvider().enumerated().map { index, screen in
            let size = pixelSize(for: screen)
            return ResolvedScreen(
                screen: screen,
                identifier: identifier(for: screen, fallbackIndex: index),
                pixelWidth: size.width,
                pixelHeight: size.height,
                backingScaleFactor: normalizedScale(screen.backingScaleFactor)
            )
        }
    }

    static func connectedScreenTargets(
        screensProvider: () -> [NSScreen] = { NSScreen.screens }
    ) -> [ScreenTarget] {
        resolvedConnectedScreens(screensProvider: screensProvider).map(\.target)
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
        do {
            return try reapplyStoredWallpapers(
                wallpapers,
                resolvedScreens: resolvedScreens,
                setDesktopImage: setDesktopImage
            )
        } catch {
            return .applyFailure
        }
    }

    @discardableResult
    static func reapplyStoredWallpapers<Screen>(
        _ wallpapers: [StoredGeneratedWallpaper],
        resolvedScreens: [ResolvedScreen<Screen>],
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows -> RestoreOutcome {
        guard !wallpapers.isEmpty else {
            return .noStoredWallpapers
        }

        guard !resolvedScreens.isEmpty else {
            return .noConnectedScreens
        }

        if
            wallpapers.count == 1,
            let wallpaper = wallpapers.first,
            wallpaper.targetIdentifier == StoredGeneratedWallpaper.allScreensTargetIdentifier
        {
            try applyWallpaper(
                imageURL: wallpaper.fileURL,
                screens: resolvedScreens.map(\.screen),
                setDesktopImage: setDesktopImage
            )
            return .fullRestore
        }

        let assignments = wallpapers.map { wallpaper in
            WallpaperAssignment(
                screenIdentifier: wallpaper.targetIdentifier,
                imageURL: wallpaper.fileURL
            )
        }
        let appliedCount = try applyWallpapers(
            assignments: assignments,
            resolvedScreens: resolvedScreens,
            setDesktopImage: setDesktopImage
        )
        return appliedCount == assignments.count ? .fullRestore : .partialRestore
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

    private static func identifier(for screen: NSScreen, fallbackIndex: Int) -> String {
        if let screenNumber = screen.deviceDescription[screenNumberKey] as? NSNumber {
            return "display-\(screenNumber.uint32Value)"
        }

        _ = fallbackIndex
        let frame = screen.frame
        let originX = Int(frame.origin.x.rounded(.toNearestOrAwayFromZero))
        let originY = Int(frame.origin.y.rounded(.toNearestOrAwayFromZero))
        let width = Int(frame.width.rounded(.toNearestOrAwayFromZero))
        let height = Int(frame.height.rounded(.toNearestOrAwayFromZero))
        return "display-fallback-\(originX)x\(originY)-\(width)x\(height)"
    }

    private static func pixelSize(for screen: NSScreen) -> (width: Int, height: Int) {
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        let width = max(Int((size.width * scale).rounded(.toNearestOrAwayFromZero)), 1)
        let height = max(Int((size.height * scale).rounded(.toNearestOrAwayFromZero)), 1)
        return (width, height)
    }

    private static func normalizedScale(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 1.0
        }
        return max(value, 1.0)
    }
}

func setWallpaper(imageURL: URL) {
    WallpaperSetter.setWallpaper(imageURL: imageURL)
}
