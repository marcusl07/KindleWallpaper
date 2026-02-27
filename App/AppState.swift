import Combine
import Dispatch
import Foundation

private let wallpaperRotationQueue = DispatchQueue(
    label: "KindleWall.AppState.WallpaperRotation",
    qos: .userInitiated
)

@MainActor
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
    typealias ExecuteRotationWork = (@escaping () -> Void) -> Void
    typealias DeliverRotationResult = (@escaping () -> Void) -> Void
    typealias Now = () -> Date

    @Published private(set) var currentQuotePreview: String
    @Published private(set) var importStatus: String
    @Published private(set) var importError: String?
    @Published private(set) var totalHighlightCount: Int
    @Published private(set) var books: [Book]
    @Published private(set) var isBookMutationInFlight: Bool
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
    private let executeRotationWork: ExecuteRotationWork
    private let deliverRotationResult: DeliverRotationResult
    private let now: Now
    private var isRotationInProgress = false
    private let bookMutationLock = NSLock()

    nonisolated private static func enqueueRotationWork(_ work: @escaping () -> Void) {
        wallpaperRotationQueue.async(execute: work)
    }

    nonisolated private static func deliverRotationResultOnMain(_ work: @escaping () -> Void) {
        DispatchQueue.main.async(execute: work)
    }

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
        executeRotationWork: @escaping ExecuteRotationWork = AppState.enqueueRotationWork,
        deliverRotationResult: @escaping DeliverRotationResult = AppState.deliverRotationResultOnMain,
        now: @escaping Now = Date.init
    ) {
        self.userDefaults = userDefaults
        self.currentQuotePreview = currentQuotePreview
        self.importStatus = importStatus
        self.importError = importError
        self.totalHighlightCount = totalHighlightCount ?? fetchTotalHighlightCount()
        self.books = books ?? fetchAllBooks()
        self.isBookMutationInFlight = false
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
        self.executeRotationWork = executeRotationWork
        self.deliverRotationResult = deliverRotationResult
        self.now = now
    }

    @discardableResult
    func rotateWallpaper() -> Bool {
        rotateWallpaperWithOutcome().didRotate
    }

    @discardableResult
    func requestWallpaperRotation() -> Bool {
        guard !isRotationInProgress else {
            return false
        }

        isRotationInProgress = true
        let context = makeRotationPipelineContext()
        executeRotationWork { [weak self] in
            let execution = AppState.runWallpaperRotationPipeline(using: context)
            self?.deliverRotationResult { [weak self] in
                guard let self else {
                    return
                }
                self.publishRotationExecution(execution)
                self.isRotationInProgress = false
            }
        }
        return true
    }

    nonisolated func requestWallpaperRotationSynchronously() -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                requestWallpaperRotation()
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                requestWallpaperRotation()
            }
        }
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

        let execution = AppState.runWallpaperRotationPipeline(using: makeRotationPipelineContext())
        publishRotationExecution(execution)
        return execution.outcome
    }

    private struct RotationPipelineContext {
        let pickNextHighlight: PickNextHighlight
        let loadBackgroundImageURL: LoadBackgroundImageURL
        let generateWallpaper: GenerateWallpaper
        let setWallpaper: SetWallpaper
        let prepareWallpaperRotation: PrepareWallpaperRotation?
        let generateWallpapers: GenerateWallpapers?
        let markHighlightShown: MarkHighlightShown
        let setLastChangedAt: (Date) -> Void
        let now: Now
    }

    private struct RotationExecution {
        let outcome: WallpaperRotationOutcome
        let currentQuotePreview: String?
        let lastChangedAt: Date?
    }

    private func makeRotationPipelineContext() -> RotationPipelineContext {
        RotationPipelineContext(
            pickNextHighlight: pickNextHighlight,
            loadBackgroundImageURL: loadBackgroundImageURL,
            generateWallpaper: generateWallpaper,
            setWallpaper: setWallpaper,
            prepareWallpaperRotation: prepareWallpaperRotation,
            generateWallpapers: generateWallpapers,
            markHighlightShown: markHighlightShown,
            setLastChangedAt: { [userDefaults] changedAt in
                userDefaults.lastChangedAt = changedAt
            },
            now: now
        )
    }

    nonisolated private static func runWallpaperRotationPipeline(using context: RotationPipelineContext) -> RotationExecution {
        guard let highlight = context.pickNextHighlight() else {
            return RotationExecution(
                outcome: .noActivePool,
                currentQuotePreview: nil,
                lastChangedAt: nil
            )
        }

        let backgroundURL = context.loadBackgroundImageURL()
        if
            let prepareWallpaperRotation = context.prepareWallpaperRotation,
            let generateWallpapers = context.generateWallpapers,
            let rotationPlan = prepareWallpaperRotation()
        {
            let targets = rotationPlan.targets
            guard !targets.isEmpty else {
                return RotationExecution(
                    outcome: .wallpaperApplyFailure(.noTargets),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }

            let generatedWallpapers = generateWallpapers(highlight, backgroundURL, targets)
            let targetIdentifiers = Set(targets.map { $0.identifier })
            let generatedIdentifiers = Set(generatedWallpapers.map { $0.targetIdentifier })

            guard
                generatedWallpapers.count == targets.count,
                generatedIdentifiers == targetIdentifiers
            else {
                return RotationExecution(
                    outcome: .wallpaperApplyFailure(.generatedTargetMismatch),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }

            do {
                try rotationPlan.apply(generatedWallpapers)
            } catch {
                return RotationExecution(
                    outcome: .wallpaperApplyFailure(.applyError),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }
        } else {
            do {
                let wallpaperURL = context.generateWallpaper(highlight, backgroundURL)
                try context.setWallpaper(wallpaperURL)
            } catch {
                return RotationExecution(
                    outcome: .wallpaperApplyFailure(.applyError),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }
        }

        context.markHighlightShown(highlight.id)
        let changedAt = context.now()
        context.setLastChangedAt(changedAt)
        return RotationExecution(
            outcome: .success,
            currentQuotePreview: highlight.quoteText,
            lastChangedAt: changedAt
        )
    }

    private func publishRotationExecution(_ execution: RotationExecution) {
        guard execution.outcome == .success else {
            return
        }
        guard
            let currentQuotePreview = execution.currentQuotePreview,
            let lastChangedAt = execution.lastChangedAt
        else {
            return
        }
        self.currentQuotePreview = currentQuotePreview
        self.lastChangedAt = lastChangedAt
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
        performBookMutation {
            guard books.first(where: { $0.id == id })?.isEnabled != enabled else {
                return false
            }
            setBookEnabledAction(id, enabled)
            return true
        }
    }

    func setAllBooksEnabled(_ enabled: Bool) {
        performBookMutation {
            guard books.contains(where: { $0.isEnabled != enabled }) else {
                return false
            }
            setAllBooksEnabledAction(enabled)
            return true
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

    private func performBookMutation(_ mutation: () -> Bool) {
        bookMutationLock.lock()
        isBookMutationInFlight = true
        defer {
            isBookMutationInFlight = false
            bookMutationLock.unlock()
        }

        guard mutation() else {
            return
        }
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
