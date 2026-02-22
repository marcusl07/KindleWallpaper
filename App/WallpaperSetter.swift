import AppKit
import Foundation

enum WallpaperSetter {
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
