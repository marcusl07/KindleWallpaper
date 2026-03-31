import AppKit
import Foundation

enum DisplayIdentityResolver {
    struct RestorePlan {
        let assignments: [WallpaperSetter.WallpaperAssignment]
        let expectedAssignmentCount: Int
    }

    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")
    private static let scaleTolerance = 0.0001

    static func resolvedConnectedScreens(
        screensProvider: () -> [NSScreen] = { NSScreen.screens }
    ) -> [WallpaperSetter.ResolvedScreen<NSScreen>] {
        screensProvider().enumerated().map { index, screen in
            let size = pixelSize(for: screen)
            let origin = roundedOrigin(for: screen.frame)
            return WallpaperSetter.ResolvedScreen(
                screen: screen,
                identifier: identifier(for: screen, fallbackIndex: index),
                pixelWidth: size.width,
                pixelHeight: size.height,
                backingScaleFactor: normalizedScale(screen.backingScaleFactor),
                originX: origin.x,
                originY: origin.y
            )
        }
    }

    static func connectedScreenTargets(
        screensProvider: () -> [NSScreen] = { NSScreen.screens }
    ) -> [WallpaperSetter.ScreenTarget] {
        resolvedConnectedScreens(screensProvider: screensProvider).map(\.target)
    }

    @discardableResult
    static func restoreStoredWallpapers<Screen>(
        _ wallpapers: [StoredGeneratedWallpaper],
        resolvedScreens: [WallpaperSetter.ResolvedScreen<Screen>],
        setDesktopImage: (URL, Screen) throws -> Void
    ) -> WallpaperSetter.RestoreOutcome {
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
        resolvedScreens: [WallpaperSetter.ResolvedScreen<Screen>],
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows -> WallpaperSetter.RestoreOutcome {
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
            try WallpaperSetter.applyWallpaper(
                imageURL: wallpaper.fileURL,
                screens: resolvedScreens.map(\.screen),
                setDesktopImage: setDesktopImage
            )
            return .fullRestore
        }

        let restorePlan = resolvedAssignments(for: wallpapers, resolvedScreens: resolvedScreens)
        let appliedCount = try WallpaperSetter.applyWallpapers(
            assignments: restorePlan.assignments,
            resolvedScreens: resolvedScreens,
            setDesktopImage: setDesktopImage
        )
        return appliedCount == restorePlan.expectedAssignmentCount ? .fullRestore : .partialRestore
    }

    static func resolvedAssignments<Screen>(
        for wallpapers: [StoredGeneratedWallpaper],
        resolvedScreens: [WallpaperSetter.ResolvedScreen<Screen>]
    ) -> RestorePlan {
        let targetedWallpapers = wallpapers.filter {
            $0.targetIdentifier != StoredGeneratedWallpaper.allScreensTargetIdentifier
        }

        guard !targetedWallpapers.isEmpty else {
            return RestorePlan(assignments: [], expectedAssignmentCount: 0)
        }

        var remainingScreenIndices = Set(resolvedScreens.indices)
        var assignedScreenIndicesByWallpaperIndex: [Int: Int] = [:]

        let storedMinimumOrigin = minimumOrigin(for: targetedWallpapers)
        let currentMinimumOrigin = minimumOrigin(for: resolvedScreens)

        func assignPending(
            _ wallpaperIndices: [Int],
            matches: (StoredGeneratedWallpaper, WallpaperSetter.ResolvedScreen<Screen>) -> Bool
        ) -> [Int] {
            var unresolvedWallpaperIndices: [Int] = []
            unresolvedWallpaperIndices.reserveCapacity(wallpaperIndices.count)

            for wallpaperIndex in wallpaperIndices {
                let candidates = remainingScreenIndices.sorted().filter { screenIndex in
                    matches(targetedWallpapers[wallpaperIndex], resolvedScreens[screenIndex])
                }

                if candidates.count == 1, let matchedScreenIndex = candidates.first {
                    assignedScreenIndicesByWallpaperIndex[wallpaperIndex] = matchedScreenIndex
                    remainingScreenIndices.remove(matchedScreenIndex)
                } else {
                    unresolvedWallpaperIndices.append(wallpaperIndex)
                }
            }

            return unresolvedWallpaperIndices
        }

        let wallpaperIndices = Array(targetedWallpapers.indices)
        let afterAbsoluteSlotMatches = assignPending(wallpaperIndices) { wallpaper, screen in
            hasComparableDisplayMetadata(wallpaper)
                && wallpaper.pixelWidth == screen.pixelWidth
                && wallpaper.pixelHeight == screen.pixelHeight
                && matchesScale(wallpaper.backingScaleFactor, screen.backingScaleFactor)
                && wallpaper.originX == screen.originX
                && wallpaper.originY == screen.originY
        }
        let afterNormalizedSlotMatches = assignPending(afterAbsoluteSlotMatches) { wallpaper, screen in
            guard
                hasComparableDisplayMetadata(wallpaper),
                let storedMinimumOrigin,
                let currentMinimumOrigin,
                let wallpaperOriginX = wallpaper.originX,
                let wallpaperOriginY = wallpaper.originY
            else {
                return false
            }

            return wallpaper.pixelWidth == screen.pixelWidth
                && wallpaper.pixelHeight == screen.pixelHeight
                && matchesScale(wallpaper.backingScaleFactor, screen.backingScaleFactor)
                && (wallpaperOriginX - storedMinimumOrigin.x) == (screen.originX - currentMinimumOrigin.x)
                && (wallpaperOriginY - storedMinimumOrigin.y) == (screen.originY - currentMinimumOrigin.y)
        }
        let afterIdentifierMatches = assignPending(afterNormalizedSlotMatches) { wallpaper, screen in
            wallpaper.targetIdentifier == screen.identifier
        }
        _ = assignPending(afterIdentifierMatches) { wallpaper, screen in
            hasComparableDisplayMetadata(wallpaper)
                && wallpaper.pixelWidth == screen.pixelWidth
                && wallpaper.pixelHeight == screen.pixelHeight
                && matchesScale(wallpaper.backingScaleFactor, screen.backingScaleFactor)
        }

        let assignments = targetedWallpapers.indices.compactMap { wallpaperIndex -> WallpaperSetter.WallpaperAssignment? in
            guard let screenIndex = assignedScreenIndicesByWallpaperIndex[wallpaperIndex] else {
                return nil
            }

            return WallpaperSetter.WallpaperAssignment(
                screenIdentifier: resolvedScreens[screenIndex].identifier,
                imageURL: targetedWallpapers[wallpaperIndex].fileURL
            )
        }

        return RestorePlan(assignments: assignments, expectedAssignmentCount: targetedWallpapers.count)
    }

    private static func hasComparableDisplayMetadata(_ wallpaper: StoredGeneratedWallpaper) -> Bool {
        wallpaper.pixelWidth != nil
            && wallpaper.pixelHeight != nil
            && wallpaper.backingScaleFactor != nil
            && wallpaper.originX != nil
            && wallpaper.originY != nil
    }

    private static func minimumOrigin(for wallpapers: [StoredGeneratedWallpaper]) -> (x: Int, y: Int)? {
        let origins = wallpapers.compactMap { wallpaper -> (x: Int, y: Int)? in
            guard let x = wallpaper.originX, let y = wallpaper.originY else {
                return nil
            }
            return (x, y)
        }
        guard let firstOrigin = origins.first else {
            return nil
        }

        return origins.dropFirst().reduce(firstOrigin) { partial, origin in
            (min(partial.x, origin.x), min(partial.y, origin.y))
        }
    }

    private static func minimumOrigin<Screen>(
        for resolvedScreens: [WallpaperSetter.ResolvedScreen<Screen>]
    ) -> (x: Int, y: Int)? {
        guard let firstScreen = resolvedScreens.first else {
            return nil
        }

        return resolvedScreens.dropFirst().reduce((firstScreen.originX, firstScreen.originY)) { partial, screen in
            (min(partial.0, screen.originX), min(partial.1, screen.originY))
        }
    }

    private static func matchesScale(_ storedScale: Double?, _ currentScale: CGFloat) -> Bool {
        guard let storedScale else {
            return false
        }
        return abs(storedScale - Double(currentScale)) < scaleTolerance
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

    private static func roundedOrigin(for frame: CGRect) -> (x: Int, y: Int) {
        (
            Int(frame.origin.x.rounded(.toNearestOrAwayFromZero)),
            Int(frame.origin.y.rounded(.toNearestOrAwayFromZero))
        )
    }

    private static func normalizedScale(_ value: CGFloat) -> CGFloat {
        guard value.isFinite else {
            return 1.0
        }
        return max(value, 1.0)
    }
}
