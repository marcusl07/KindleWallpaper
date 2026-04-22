import Foundation

enum QuotesListSortMode {
    case mostRecentlyAdded
}

struct QuotesListFilters: Equatable {
    init() {}
}

struct QuoteEditSaveRequest {
    let quoteText: String
    let bookTitle: String
    let author: String
    let location: String
    let bookId: UUID?
}

enum WallpaperSetter {
    enum RestoreOutcome: Equatable {
        case fullRestore
        case partialRestore
        case noStoredWallpapers
        case noConnectedScreens
        case applyFailure
    }

    struct ResolvedScreen<Screen> {
        let screen: Screen
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
        let backingScaleFactor: CGFloat
        let originX: Int
        let originY: Int
    }

    struct WallpaperAssignment {
        let screenIdentifier: String
        let imageURL: URL
    }

    typealias CurrentDesktopImageURL<Screen> = (Screen) -> URL?

    static func applySharedWallpaper<Screen>(
        imageURL: URL,
        resolvedScreens: [ResolvedScreen<Screen>],
        currentDesktopImageURL: CurrentDesktopImageURL<Screen>? = nil,
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows -> Int {
        0
    }
}
