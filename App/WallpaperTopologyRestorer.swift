import Foundation

enum WallpaperTopologyReapplyOutcome: Equatable {
    case reapplied
    case alreadyApplied
    case noConnectedScreens
    case noCurrentWallpaper
    case applyFailure
}

struct WallpaperTopologyRestorer<Screen> {
    let loadStoredWallpapers: () -> [StoredGeneratedWallpaper]
    let resolvedScreens: () -> [WallpaperSetter.ResolvedScreen<Screen>]
    let preferredSourceScreen: () -> Screen?
    let sameScreen: (Screen, Screen) -> Bool
    let currentDesktopImageURL: WallpaperSetter.CurrentDesktopImageURL<Screen>
    let setDesktopImage: (URL, Screen) throws -> Void

    func reapply() -> WallpaperTopologyReapplyOutcome {
        Self.reapply(
            resolvedScreens: resolvedScreens(),
            storedWallpapers: loadStoredWallpapers(),
            preferredSourceScreen: preferredSourceScreen(),
            sameScreen: sameScreen,
            currentDesktopImageURL: currentDesktopImageURL,
            setDesktopImage: setDesktopImage
        )
    }

    static func reapply(
        resolvedScreens: [WallpaperSetter.ResolvedScreen<Screen>],
        storedWallpapers: [StoredGeneratedWallpaper] = [],
        preferredSourceScreen: Screen?,
        sameScreen: (Screen, Screen) -> Bool,
        currentDesktopImageURL: @escaping WallpaperSetter.CurrentDesktopImageURL<Screen>,
        setDesktopImage: (URL, Screen) throws -> Void
    ) -> WallpaperTopologyReapplyOutcome {
        guard !resolvedScreens.isEmpty else {
            return .noConnectedScreens
        }

        let sourceScreens = topologyWallpaperSourceScreens(
            resolvedScreens: resolvedScreens,
            preferredSourceScreen: preferredSourceScreen,
            sameScreen: sameScreen
        )

        guard let imageURL = topologyWallpaperSourceURL(
            storedWallpapers: storedWallpapers,
            sourceScreens: sourceScreens,
            currentDesktopImageURL: currentDesktopImageURL
        ) else {
            return .noCurrentWallpaper
        }

        do {
            let appliedCount = try WallpaperSetter.applySharedWallpaper(
                imageURL: imageURL,
                resolvedScreens: resolvedScreens,
                currentDesktopImageURL: currentDesktopImageURL,
                setDesktopImage: setDesktopImage
            )
            return appliedCount == 0 ? .alreadyApplied : .reapplied
        } catch {
            return .applyFailure
        }
    }

    private static func topologyWallpaperSourceURL(
        storedWallpapers: [StoredGeneratedWallpaper],
        sourceScreens: [WallpaperSetter.ResolvedScreen<Screen>],
        currentDesktopImageURL: WallpaperSetter.CurrentDesktopImageURL<Screen>
    ) -> URL? {
        let preferredResolvedScreen = sourceScreens.first
        let firstResolvedScreen = sourceScreens.last ?? preferredResolvedScreen

        let persistedSourceIdentifiers = [
            preferredResolvedScreen?.identifier,
            firstResolvedScreen?.identifier
        ].compactMap { $0 }

        for identifier in persistedSourceIdentifiers {
            if let fileURL = storedWallpapers.first(where: { $0.targetIdentifier == identifier })?.fileURL {
                return fileURL
            }
        }

        if let sharedFileURL = storedWallpapers.first(where: {
            $0.targetIdentifier == StoredGeneratedWallpaper.allScreensTargetIdentifier
        })?.fileURL {
            return sharedFileURL
        }

        for screen in sourceScreens.map(\.screen) {
            if let imageURL = currentDesktopImageURL(screen) {
                return imageURL
            }
        }

        return nil
    }

    private static func topologyWallpaperSourceScreens(
        resolvedScreens: [WallpaperSetter.ResolvedScreen<Screen>],
        preferredSourceScreen: Screen?,
        sameScreen: (Screen, Screen) -> Bool
    ) -> [WallpaperSetter.ResolvedScreen<Screen>] {
        var sourceScreens: [WallpaperSetter.ResolvedScreen<Screen>] = []
        sourceScreens.reserveCapacity(2)

        if
            let preferredSourceScreen,
            let preferredResolvedScreen = resolvedScreens.first(where: { sameScreen($0.screen, preferredSourceScreen) })
        {
            sourceScreens.append(preferredResolvedScreen)
        }

        if let firstResolvedScreen = resolvedScreens.first {
            let alreadyIncludedFirstScreen = sourceScreens.contains { candidate in
                sameScreen(candidate.screen, firstResolvedScreen.screen)
            }

            if !alreadyIncludedFirstScreen {
                sourceScreens.append(firstResolvedScreen)
            }
        }

        return sourceScreens
    }
}
