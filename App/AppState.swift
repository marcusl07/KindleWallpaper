import Combine
import Foundation

final class AppState: ObservableObject {
    typealias PickNextHighlight = () -> Highlight?
    typealias LoadBackgroundImageURL = () -> URL?
    typealias GenerateWallpaper = (Highlight, URL?) -> URL
    typealias SetWallpaper = (URL) -> Void
    typealias MarkHighlightShown = (UUID) -> Void
    typealias Now = () -> Date

    @Published private(set) var currentQuotePreview: String
    @Published private(set) var lastChangedAt: Date?

    private let userDefaults: UserDefaults
    private let pickNextHighlight: PickNextHighlight
    private let loadBackgroundImageURL: LoadBackgroundImageURL
    private let generateWallpaper: GenerateWallpaper
    private let setWallpaper: SetWallpaper
    private let markHighlightShown: MarkHighlightShown
    private let now: Now
    private var isRotationInProgress = false

    init(
        userDefaults: UserDefaults = .standard,
        currentQuotePreview: String = "",
        pickNextHighlight: @escaping PickNextHighlight,
        loadBackgroundImageURL: @escaping LoadBackgroundImageURL,
        generateWallpaper: @escaping GenerateWallpaper,
        setWallpaper: @escaping SetWallpaper,
        markHighlightShown: @escaping MarkHighlightShown,
        now: @escaping Now = Date.init
    ) {
        self.userDefaults = userDefaults
        self.currentQuotePreview = currentQuotePreview
        self.lastChangedAt = userDefaults.lastChangedAt
        self.pickNextHighlight = pickNextHighlight
        self.loadBackgroundImageURL = loadBackgroundImageURL
        self.generateWallpaper = generateWallpaper
        self.setWallpaper = setWallpaper
        self.markHighlightShown = markHighlightShown
        self.now = now
    }

    func rotateWallpaper() {
        guard !isRotationInProgress else {
            return
        }

        isRotationInProgress = true
        defer {
            isRotationInProgress = false
        }

        guard let highlight = pickNextHighlight() else {
            return
        }

        let backgroundURL = loadBackgroundImageURL()
        let wallpaperURL = generateWallpaper(highlight, backgroundURL)
        setWallpaper(wallpaperURL)
        markHighlightShown(highlight.id)

        let changedAt = now()
        userDefaults.lastChangedAt = changedAt
        lastChangedAt = changedAt
        currentQuotePreview = highlight.quoteText
    }
}

#if canImport(GRDB)
extension AppState {
    static func live(userDefaults: UserDefaults = .standard) -> AppState {
        let backgroundStore = BackgroundImageStore(userDefaults: userDefaults)
        let wallpaperGenerator = WallpaperGenerator()

        return AppState(
            userDefaults: userDefaults,
            pickNextHighlight: DatabaseManager.pickNextHighlight,
            loadBackgroundImageURL: backgroundStore.loadBackgroundImageURL,
            generateWallpaper: { highlight, backgroundURL in
                wallpaperGenerator.generateWallpaper(highlight: highlight, backgroundURL: backgroundURL)
            },
            setWallpaper: { imageURL in
                setWallpaper(imageURL: imageURL)
            },
            markHighlightShown: DatabaseManager.markHighlightShown(id:)
        )
    }
}
#endif
