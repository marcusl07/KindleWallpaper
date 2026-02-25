import Combine
import Foundation

final class AppState: ObservableObject {
    struct WallpaperTarget: Equatable {
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
        let backingScaleFactor: CGFloat
    }

    struct GeneratedWallpaper: Equatable {
        let targetIdentifier: String
        let fileURL: URL
    }

    struct WallpaperRotationPlan {
        let targets: [WallpaperTarget]
        private let applyGeneratedWallpapers: ([GeneratedWallpaper]) throws -> Void

        init(targets: [WallpaperTarget], applyGeneratedWallpapers: @escaping ([GeneratedWallpaper]) throws -> Void) {
            self.targets = targets
            self.applyGeneratedWallpapers = applyGeneratedWallpapers
        }

        func apply(_ generatedWallpapers: [GeneratedWallpaper]) throws {
            try applyGeneratedWallpapers(generatedWallpapers)
        }
    }

    enum WallpaperApplyFailureReason: Equatable {
        case noTargets
        case generatedTargetMismatch
        case applyError
    }

    enum WallpaperRotationOutcome: Equatable {
        case success
        case alreadyInProgress
        case noActivePool
        case wallpaperApplyFailure(WallpaperApplyFailureReason)

        var didRotate: Bool {
            if case .success = self {
                return true
            }
            return false
        }
    }

    typealias PickNextHighlight = () -> Highlight?
    typealias LoadBackgroundImageURL = () -> URL?
    typealias GenerateWallpaper = (Highlight, URL?) -> URL
    typealias SetWallpaper = (URL) throws -> Void
    typealias PrepareWallpaperRotation = () -> WallpaperRotationPlan?
    typealias GenerateWallpapers = (Highlight, URL?, [WallpaperTarget]) -> [GeneratedWallpaper]
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
    private let prepareWallpaperRotation: PrepareWallpaperRotation?
    private let generateWallpapers: GenerateWallpapers?
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
        prepareWallpaperRotation: PrepareWallpaperRotation? = nil,
        generateWallpapers: GenerateWallpapers? = nil,
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
        self.prepareWallpaperRotation = prepareWallpaperRotation
        self.generateWallpapers = generateWallpapers
        self.markHighlightShown = markHighlightShown
        self.setBookEnabledAction = setBookEnabled
        self.setAllBooksEnabledAction = setAllBooksEnabled
        self.fetchAllBooks = fetchAllBooks
        self.fetchTotalHighlightCount = fetchTotalHighlightCount
        self.now = now
    }

    @discardableResult
    func rotateWallpaper() -> Bool {
        rotateWallpaperWithOutcome().didRotate
    }

    @discardableResult
    func rotateWallpaperWithOutcome() -> WallpaperRotationOutcome {
        guard !isRotationInProgress else {
            return .alreadyInProgress
        }

        isRotationInProgress = true
        defer {
            isRotationInProgress = false
        }

        guard let highlight = pickNextHighlight() else {
            return .noActivePool
        }

        let backgroundURL = loadBackgroundImageURL()
        if
            let prepareWallpaperRotation,
            let generateWallpapers,
            let rotationPlan = prepareWallpaperRotation()
        {
            let targets = rotationPlan.targets
            guard !targets.isEmpty else {
                return .wallpaperApplyFailure(.noTargets)
            }

            let generatedWallpapers = generateWallpapers(highlight, backgroundURL, targets)
            let targetIdentifiers = Set(targets.map { $0.identifier })
            let generatedIdentifiers = Set(generatedWallpapers.map { $0.targetIdentifier })

            guard
                generatedWallpapers.count == targets.count,
                generatedIdentifiers == targetIdentifiers
            else {
                return .wallpaperApplyFailure(.generatedTargetMismatch)
            }

            do {
                try rotationPlan.apply(generatedWallpapers)
            } catch {
                return .wallpaperApplyFailure(.applyError)
            }
        } else {
            do {
                let wallpaperURL = generateWallpaper(highlight, backgroundURL)
                try setWallpaper(wallpaperURL)
            } catch {
                return .wallpaperApplyFailure(.applyError)
            }
        }

        markHighlightShown(highlight.id)

        let changedAt = now()
        userDefaults.lastChangedAt = changedAt
        lastChangedAt = changedAt
        currentQuotePreview = highlight.quoteText
        return .success
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
        guard books.first(where: { $0.id == id })?.isEnabled != enabled else {
            return
        }
        performBookMutation {
            setBookEnabledAction(id, enabled)
        }
    }

    func setAllBooksEnabled(_ enabled: Bool) {
        guard books.contains(where: { $0.isEnabled != enabled }) else {
            return
        }
        performBookMutation {
            setAllBooksEnabledAction(enabled)
        }
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

    private func performBookMutation(_ mutation: () -> Void) {
        mutation()
        refreshLibraryState()
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
                try WallpaperSetter.trySetWallpaper(imageURL: imageURL)
            },
            prepareWallpaperRotation: {
                let resolvedScreens = WallpaperSetter.resolvedConnectedScreens()
                guard !resolvedScreens.isEmpty else {
                    return nil
                }
                let targets = resolvedScreens.map { screen in
                    WallpaperTarget(
                        identifier: screen.identifier,
                        pixelWidth: screen.pixelWidth,
                        pixelHeight: screen.pixelHeight,
                        backingScaleFactor: screen.backingScaleFactor
                    )
                }
                return WallpaperRotationPlan(targets: targets) { generatedWallpapers in
                    let assignments = generatedWallpapers.map { generated in
                        WallpaperSetter.WallpaperAssignment(
                            screenIdentifier: generated.targetIdentifier,
                            imageURL: generated.fileURL
                        )
                    }
                    try WallpaperSetter.trySetWallpapers(assignments: assignments, on: resolvedScreens)
                }
            },
            generateWallpapers: { highlight, backgroundURL, targets in
                let generatorTargets = targets.map { target in
                    WallpaperGenerator.RenderTarget(
                        identifier: target.identifier,
                        pixelWidth: target.pixelWidth,
                        pixelHeight: target.pixelHeight,
                        backingScaleFactor: target.backingScaleFactor
                    )
                }
                return wallpaperGenerator.generateWallpapers(
                    highlight: highlight,
                    backgroundURL: backgroundURL,
                    targets: generatorTargets
                ).map { generated in
                    GeneratedWallpaper(
                        targetIdentifier: generated.targetIdentifier,
                        fileURL: generated.fileURL
                    )
                }
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
