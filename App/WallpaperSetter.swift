import AppKit
import Foundation

enum WallpaperSetter {
    struct ScreenTarget: Equatable {
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
    }

    struct WallpaperAssignment: Equatable {
        let screenIdentifier: String
        let imageURL: URL
    }

    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    static func connectedScreenTargets(
        screensProvider: () -> [NSScreen] = { NSScreen.screens }
    ) -> [ScreenTarget] {
        screensProvider().enumerated().map { index, screen in
            let size = pixelSize(for: screen)
            return ScreenTarget(
                identifier: identifier(for: screen, fallbackIndex: index),
                pixelWidth: size.width,
                pixelHeight: size.height
            )
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
            try applyWallpapers(
                assignments: assignments,
                screens: screensProvider(),
                screenIdentifier: { screen, index in
                    identifier(for: screen, fallbackIndex: index)
                },
                setDesktopImage: setDesktopImage
            )
        } catch {
            fatalError("Failed to set wallpaper for targeted screens: \(error)")
        }
    }

    static func setWallpaper(
        imageURL: URL,
        screensProvider: () -> [NSScreen] = { NSScreen.screens },
        setDesktopImage: (URL, NSScreen) throws -> Void = { url, screen in
            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
        }
    ) {
        do {
            try applyWallpaper(imageURL: imageURL, screens: screensProvider(), setDesktopImage: setDesktopImage)
        } catch {
            fatalError("Failed to set wallpaper for all screens: \(error)")
        }
    }

    static func applyWallpapers<Screen>(
        assignments: [WallpaperAssignment],
        screens: [Screen],
        screenIdentifier: (Screen, Int) -> String,
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows {
        let urlsByIdentifier = Dictionary(
            assignments.map { assignment in
                (assignment.screenIdentifier, assignment.imageURL)
            },
            uniquingKeysWith: { _, latest in latest }
        )

        for (index, screen) in screens.enumerated() {
            let identifier = screenIdentifier(screen, index)
            guard let imageURL = urlsByIdentifier[identifier] else {
                continue
            }
            try setDesktopImage(imageURL, screen)
        }
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

        let frame = screen.frame
        return "display-fallback-\(fallbackIndex)-\(Int(frame.width))x\(Int(frame.height))"
    }

    private static func pixelSize(for screen: NSScreen) -> (width: Int, height: Int) {
        let size = screen.frame.size
        let scale = screen.backingScaleFactor
        let width = max(Int((size.width * scale).rounded(.toNearestOrAwayFromZero)), 1)
        let height = max(Int((size.height * scale).rounded(.toNearestOrAwayFromZero)), 1)
        return (width, height)
    }
}

func setWallpaper(imageURL: URL) {
    WallpaperSetter.setWallpaper(imageURL: imageURL)
}
