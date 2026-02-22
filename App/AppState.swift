import Combine
import Foundation

final class AppState: ObservableObject {
    typealias WallpaperTarget = (identifier: String, pixelWidth: Int, pixelHeight: Int)
    typealias GeneratedWallpaper = (targetIdentifier: String, fileURL: URL)
    typealias PickNextHighlight = () -> Highlight?
    typealias LoadBackgroundImageURL = () -> URL?
    typealias GenerateWallpaper = (Highlight, URL?) -> URL
    typealias SetWallpaper = (URL) -> Void
    typealias FetchWallpaperTargets = () -> [WallpaperTarget]
    typealias GenerateWallpapers = (Highlight, URL?, [WallpaperTarget]) -> [GeneratedWallpaper]
    typealias SetWallpapers = ([GeneratedWallpaper]) -> Void
    typealias MarkHighlightShown = (UUID) -> Void
    typealias SetBookEnabled = (UUID, Bool) -> Void
    typealias SetAllBooksEnabled = (Bool) -> Void
    typealias FetchAllBooks = () -> [Book]
    typealias FetchTotalHighlightCount = () -> Int
    typealias Now = () -> Date

    @Published private(set) var currentQuotePreview: String
    @Published private(set) var importStatus: String
    @Published private(set) var importError: String?
    @Published private(set) var totalHighlightCount: Int
    @Published private(set) var books: [Book]
    @Published private(set) var activeScheduleMode: RotationScheduleMode
    @Published private(set) var lastChangedAt: Date?

    private let userDefaults: UserDefaults
    private let pickNextHighlight: PickNextHighlight
    private let loadBackgroundImageURL: LoadBackgroundImageURL
    private let generateWallpaper: GenerateWallpaper
    private let setWallpaper: SetWallpaper
    private let fetchWallpaperTargets: FetchWallpaperTargets?
    private let generateWallpapers: GenerateWallpapers?
    private let setWallpapers: SetWallpapers?
    private let markHighlightShown: MarkHighlightShown
    private let setBookEnabledAction: SetBookEnabled
    private let setAllBooksEnabledAction: SetAllBooksEnabled
    private let fetchAllBooks: FetchAllBooks
    private let fetchTotalHighlightCount: FetchTotalHighlightCount
    private let now: Now
    private var isRotationInProgress = false

    init(
        userDefaults: UserDefaults = .standard,
        currentQuotePreview: String = "",
        importStatus: String = "",
        importError: String? = nil,
        totalHighlightCount: Int? = nil,
        books: [Book]? = nil,
        activeScheduleMode: RotationScheduleMode? = nil,
        pickNextHighlight: @escaping PickNextHighlight,
        loadBackgroundImageURL: @escaping LoadBackgroundImageURL,
        generateWallpaper: @escaping GenerateWallpaper,
        setWallpaper: @escaping SetWallpaper,
        fetchWallpaperTargets: FetchWallpaperTargets? = nil,
        generateWallpapers: GenerateWallpapers? = nil,
        setWallpapers: SetWallpapers? = nil,
        markHighlightShown: @escaping MarkHighlightShown,
        setBookEnabled: @escaping SetBookEnabled = { _, _ in },
        setAllBooksEnabled: @escaping SetAllBooksEnabled = { _ in },
        fetchAllBooks: @escaping FetchAllBooks = { [] },
        fetchTotalHighlightCount: @escaping FetchTotalHighlightCount = { 0 },
        now: @escaping Now = Date.init
    ) {
        self.userDefaults = userDefaults
        self.currentQuotePreview = currentQuotePreview
        self.importStatus = importStatus
        self.importError = importError
        self.totalHighlightCount = totalHighlightCount ?? fetchTotalHighlightCount()
        self.books = books ?? fetchAllBooks()
        self.activeScheduleMode = activeScheduleMode ?? userDefaults.rotationScheduleMode
        self.lastChangedAt = userDefaults.lastChangedAt
        self.pickNextHighlight = pickNextHighlight
        self.loadBackgroundImageURL = loadBackgroundImageURL
        self.generateWallpaper = generateWallpaper
        self.setWallpaper = setWallpaper
        self.fetchWallpaperTargets = fetchWallpaperTargets
        self.generateWallpapers = generateWallpapers
        self.setWallpapers = setWallpapers
        self.markHighlightShown = markHighlightShown
        self.setBookEnabledAction = setBookEnabled
        self.setAllBooksEnabledAction = setAllBooksEnabled
        self.fetchAllBooks = fetchAllBooks
        self.fetchTotalHighlightCount = fetchTotalHighlightCount
        self.now = now
    }

    @discardableResult
    func rotateWallpaper() -> Bool {
        guard !isRotationInProgress else {
            return false
        }

        isRotationInProgress = true
        defer {
            isRotationInProgress = false
        }

        guard let highlight = pickNextHighlight() else {
            return false
        }

        let backgroundURL = loadBackgroundImageURL()
        if
            let fetchWallpaperTargets,
            let generateWallpapers,
            let setWallpapers
        {
            let targets = fetchWallpaperTargets()
            guard !targets.isEmpty else {
                return false
            }

            let generatedWallpapers = generateWallpapers(highlight, backgroundURL, targets)
            let targetIdentifiers = Set(targets.map { $0.identifier })
            let generatedIdentifiers = Set(generatedWallpapers.map { $0.targetIdentifier })

            guard
                generatedWallpapers.count == targets.count,
                generatedIdentifiers == targetIdentifiers
            else {
                return false
            }

            setWallpapers(generatedWallpapers)
        } else {
            let wallpaperURL = generateWallpaper(highlight, backgroundURL)
            setWallpaper(wallpaperURL)
        }

        markHighlightShown(highlight.id)

        let changedAt = now()
        userDefaults.lastChangedAt = changedAt
        lastChangedAt = changedAt
        currentQuotePreview = highlight.quoteText
        return true
    }

    func setImportStatus(_ message: String, isError: Bool) {
        let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if isError {
            importStatus = ""
            importError = normalizedMessage.isEmpty ? "Import failed: unknown error." : normalizedMessage
            return
        }

        importStatus = normalizedMessage
        importError = nil
    }

    func refreshLibraryState() {
        totalHighlightCount = fetchTotalHighlightCount()
        books = fetchAllBooks()
    }

    func setBookEnabled(id: UUID, enabled: Bool) {
        setBookEnabledAction(id, enabled)
        books = fetchAllBooks()
    }

    func setAllBooksEnabled(_ enabled: Bool) {
        guard books.contains(where: { $0.isEnabled != enabled }) else {
            return
        }
        setAllBooksEnabledAction(enabled)
        books = fetchAllBooks()
    }

    func refreshScheduleState() {
        activeScheduleMode = userDefaults.rotationScheduleMode
        lastChangedAt = userDefaults.lastChangedAt
    }

    func refreshAllState() {
        refreshLibraryState()
        refreshScheduleState()
    }

    func setActiveScheduleMode(_ mode: RotationScheduleMode) {
        userDefaults.rotationScheduleMode = mode
        activeScheduleMode = mode
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
                WallpaperSetter.setWallpaper(imageURL: imageURL)
            },
            fetchWallpaperTargets: {
                WallpaperSetter.connectedScreenTargets().map { target in
                    (identifier: target.identifier, pixelWidth: target.pixelWidth, pixelHeight: target.pixelHeight)
                }
            },
            generateWallpapers: { highlight, backgroundURL, targets in
                let generatorTargets = targets.map { target in
                    WallpaperGenerator.RenderTarget(
                        identifier: target.identifier,
                        pixelWidth: target.pixelWidth,
                        pixelHeight: target.pixelHeight
                    )
                }
                return wallpaperGenerator.generateWallpapers(
                    highlight: highlight,
                    backgroundURL: backgroundURL,
                    targets: generatorTargets
                ).map { generated in
                    (targetIdentifier: generated.targetIdentifier, fileURL: generated.fileURL)
                }
            },
            setWallpapers: { generatedWallpapers in
                let assignments = generatedWallpapers.map { generated in
                    WallpaperSetter.WallpaperAssignment(
                        screenIdentifier: generated.targetIdentifier,
                        imageURL: generated.fileURL
                    )
                }
                WallpaperSetter.setWallpapers(assignments: assignments)
            },
            markHighlightShown: DatabaseManager.markHighlightShown(id:),
            setBookEnabled: DatabaseManager.setBookEnabled(id:enabled:),
            setAllBooksEnabled: DatabaseManager.setAllBooksEnabled(enabled:),
            fetchAllBooks: DatabaseManager.fetchAllBooks,
            fetchTotalHighlightCount: DatabaseManager.totalHighlightCount
        )
    }
}
#endif
