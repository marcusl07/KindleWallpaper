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

    struct BackgroundPreviewState: Equatable {
        let primaryImageURL: URL?
        let warningMessage: String?
    }

    struct BackgroundCollectionItem: Equatable, Identifiable {
        let id: UUID
        let fileURL: URL
        let addedAt: Date
    }

    struct BackgroundCollectionState: Equatable {
        let items: [BackgroundCollectionItem]
        let selectedItemID: UUID?
        let warningMessage: String?
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
    typealias LoadBackgroundImageURLs = () -> [URL]
    typealias LoadBackgroundImageURL = () -> URL?
    typealias SelectBackgroundImageURL = ([URL]) -> URL?
    typealias GenerateWallpaper = (Highlight, URL?) -> URL
    typealias SetWallpaper = (URL) throws -> Void
    typealias PrepareWallpaperRotation = () -> WallpaperRotationPlan?
    typealias GenerateWallpapers = (Highlight, URL?, [WallpaperTarget]) -> [GeneratedWallpaper]
    typealias StoreReusableGeneratedWallpapers = ([GeneratedWallpaper]) -> Void
    typealias ReapplyStoredWallpaper = () -> Bool
    typealias MarkHighlightShown = (UUID) -> Void
    typealias SetBookEnabled = (UUID, Bool) -> Void
    typealias SetAllBooksEnabled = (Bool) -> Void
    typealias FetchAllBooks = () -> [Book]
    typealias FetchTotalHighlightCount = () -> Int
    typealias LoadBackgroundPreviewState = () -> BackgroundPreviewState
    typealias SaveBackgroundImageSelection = (URL) throws -> Void
    typealias LoadBackgroundCollectionState = () -> BackgroundCollectionState
    typealias AddBackgroundImageSelection = (URL) throws -> Void
    typealias RemoveBackgroundImageSelection = (UUID) throws -> Void
    typealias SetPrimaryBackgroundImageSelection = (UUID) throws -> Void
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
    @Published private(set) var capitalizeHighlightText: Bool

    private let userDefaults: UserDefaults
    private let pickNextHighlight: PickNextHighlight
    private let loadBackgroundImageURLs: LoadBackgroundImageURLs
    private let selectBackgroundImageURL: SelectBackgroundImageURL
    private let generateWallpaper: GenerateWallpaper
    private let setWallpaper: SetWallpaper
    private let prepareWallpaperRotation: PrepareWallpaperRotation?
    private let generateWallpapers: GenerateWallpapers?
    private let storeReusableGeneratedWallpapers: StoreReusableGeneratedWallpapers
    private let reapplyStoredWallpaper: ReapplyStoredWallpaper
    private let markHighlightShown: MarkHighlightShown
    private let setBookEnabledAction: SetBookEnabled
    private let setAllBooksEnabledAction: SetAllBooksEnabled
    private let fetchAllBooks: FetchAllBooks
    private let fetchTotalHighlightCount: FetchTotalHighlightCount
    private let loadBackgroundPreviewStateAction: LoadBackgroundPreviewState
    private let saveBackgroundImageSelectionAction: SaveBackgroundImageSelection
    private let loadBackgroundCollectionStateAction: LoadBackgroundCollectionState
    private let addBackgroundImageSelectionAction: AddBackgroundImageSelection
    private let removeBackgroundImageSelectionAction: RemoveBackgroundImageSelection
    private let setPrimaryBackgroundImageSelectionAction: SetPrimaryBackgroundImageSelection
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
        loadBackgroundImageURLs: LoadBackgroundImageURLs? = nil,
        loadBackgroundImageURL: @escaping LoadBackgroundImageURL = { nil },
        selectBackgroundImageURL: SelectBackgroundImageURL? = nil,
        generateWallpaper: @escaping GenerateWallpaper,
        setWallpaper: @escaping SetWallpaper,
        prepareWallpaperRotation: PrepareWallpaperRotation? = nil,
        generateWallpapers: GenerateWallpapers? = nil,
        storeReusableGeneratedWallpapers: @escaping StoreReusableGeneratedWallpapers = { _ in },
        reapplyStoredWallpaper: @escaping ReapplyStoredWallpaper = { false },
        markHighlightShown: @escaping MarkHighlightShown,
        setBookEnabled: @escaping SetBookEnabled = { _, _ in },
        setAllBooksEnabled: @escaping SetAllBooksEnabled = { _ in },
        fetchAllBooks: @escaping FetchAllBooks = { [] },
        fetchTotalHighlightCount: @escaping FetchTotalHighlightCount = { 0 },
        loadBackgroundPreviewState: LoadBackgroundPreviewState? = nil,
        saveBackgroundImageSelection: @escaping SaveBackgroundImageSelection = { _ in },
        loadBackgroundCollectionState: LoadBackgroundCollectionState? = nil,
        addBackgroundImageSelection: @escaping AddBackgroundImageSelection = { _ in },
        removeBackgroundImageSelection: @escaping RemoveBackgroundImageSelection = { _ in },
        setPrimaryBackgroundImageSelection: @escaping SetPrimaryBackgroundImageSelection = { _ in },
        executeRotationWork: @escaping ExecuteRotationWork = AppState.enqueueRotationWork,
        deliverRotationResult: @escaping DeliverRotationResult = AppState.deliverRotationResultOnMain,
        now: @escaping Now = Date.init
    ) {
        let resolvedLoadBackgroundImageURLs: LoadBackgroundImageURLs
        if let loadBackgroundImageURLs {
            resolvedLoadBackgroundImageURLs = loadBackgroundImageURLs
        } else {
            resolvedLoadBackgroundImageURLs = {
                guard let url = loadBackgroundImageURL() else {
                    return []
                }
                return [url]
            }
        }

        let resolvedSelectBackgroundImageURL: SelectBackgroundImageURL
        if let selectBackgroundImageURL {
            resolvedSelectBackgroundImageURL = selectBackgroundImageURL
        } else {
            resolvedSelectBackgroundImageURL = { backgroundURLs in
                guard backgroundURLs.count > 1 else {
                    return backgroundURLs.first
                }
                return backgroundURLs.randomElement()
            }
        }

        let resolvedLoadBackgroundPreviewState: LoadBackgroundPreviewState
        if let loadBackgroundPreviewState {
            resolvedLoadBackgroundPreviewState = loadBackgroundPreviewState
        } else {
            resolvedLoadBackgroundPreviewState = {
                let backgroundURLs = resolvedLoadBackgroundImageURLs()
                return BackgroundPreviewState(
                    primaryImageURL: backgroundURLs.first,
                    warningMessage: nil
                )
            }
        }

        let resolvedLoadBackgroundCollectionState: LoadBackgroundCollectionState
        if let loadBackgroundCollectionState {
            resolvedLoadBackgroundCollectionState = loadBackgroundCollectionState
        } else {
            resolvedLoadBackgroundCollectionState = {
                let previewState = resolvedLoadBackgroundPreviewState()
                let items = resolvedLoadBackgroundImageURLs().map { fileURL in
                    BackgroundCollectionItem(
                        id: UUID(),
                        fileURL: fileURL,
                        addedAt: .distantPast
                    )
                }
                return BackgroundCollectionState(
                    items: items,
                    selectedItemID: previewState.primaryImageURL.flatMap { selectedURL in
                        items.first(where: { $0.fileURL == selectedURL })?.id
                    },
                    warningMessage: previewState.warningMessage
                )
            }
        }

        self.userDefaults = userDefaults
        self.currentQuotePreview = currentQuotePreview
        self.importStatus = importStatus
        self.importError = importError
        self.totalHighlightCount = totalHighlightCount ?? fetchTotalHighlightCount()
        self.books = books ?? fetchAllBooks()
        self.isBookMutationInFlight = false
        self.activeScheduleMode = activeScheduleMode ?? userDefaults.rotationScheduleMode
        self.lastChangedAt = userDefaults.lastChangedAt
        self.capitalizeHighlightText = userDefaults.capitalizeHighlightText
        self.pickNextHighlight = pickNextHighlight
        self.loadBackgroundImageURLs = resolvedLoadBackgroundImageURLs
        self.selectBackgroundImageURL = resolvedSelectBackgroundImageURL
        self.generateWallpaper = generateWallpaper
        self.setWallpaper = setWallpaper
        self.prepareWallpaperRotation = prepareWallpaperRotation
        self.generateWallpapers = generateWallpapers
        self.storeReusableGeneratedWallpapers = storeReusableGeneratedWallpapers
        self.reapplyStoredWallpaper = reapplyStoredWallpaper
        self.markHighlightShown = markHighlightShown
        self.setBookEnabledAction = setBookEnabled
        self.setAllBooksEnabledAction = setAllBooksEnabled
        self.fetchAllBooks = fetchAllBooks
        self.fetchTotalHighlightCount = fetchTotalHighlightCount
        self.loadBackgroundPreviewStateAction = resolvedLoadBackgroundPreviewState
        self.saveBackgroundImageSelectionAction = saveBackgroundImageSelection
        self.loadBackgroundCollectionStateAction = resolvedLoadBackgroundCollectionState
        self.addBackgroundImageSelectionAction = addBackgroundImageSelection
        self.removeBackgroundImageSelectionAction = removeBackgroundImageSelection
        self.setPrimaryBackgroundImageSelectionAction = setPrimaryBackgroundImageSelection
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

    @discardableResult
    func reapplyStoredWallpaperIfAvailable() -> Bool {
        reapplyStoredWallpaper()
    }

    private struct RotationPipelineContext {
        let pickNextHighlight: PickNextHighlight
        let loadBackgroundImageURLs: LoadBackgroundImageURLs
        let selectBackgroundImageURL: SelectBackgroundImageURL
        let transformQuoteTextForDisplay: (String) -> String
        let generateWallpaper: GenerateWallpaper
        let setWallpaper: SetWallpaper
        let prepareWallpaperRotation: PrepareWallpaperRotation?
        let generateWallpapers: GenerateWallpapers?
        let storeReusableGeneratedWallpapers: StoreReusableGeneratedWallpapers
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
        let capitalizeHighlightText = userDefaults.capitalizeHighlightText
        return RotationPipelineContext(
            pickNextHighlight: pickNextHighlight,
            loadBackgroundImageURLs: loadBackgroundImageURLs,
            selectBackgroundImageURL: selectBackgroundImageURL,
            transformQuoteTextForDisplay: { quoteText in
                AppState.transformedQuoteTextForDisplay(
                    quoteText,
                    capitalizeFirstLetterIfLowercase: capitalizeHighlightText
                )
            },
            generateWallpaper: generateWallpaper,
            setWallpaper: setWallpaper,
            prepareWallpaperRotation: prepareWallpaperRotation,
            generateWallpapers: generateWallpapers,
            storeReusableGeneratedWallpapers: storeReusableGeneratedWallpapers,
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

        let displayQuoteText = context.transformQuoteTextForDisplay(highlight.quoteText)
        let highlightForDisplay = displayHighlight(highlight, quoteText: displayQuoteText)
        let backgroundURL = context.selectBackgroundImageURL(context.loadBackgroundImageURLs())
        let appliedGeneratedWallpapers: [GeneratedWallpaper]
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

            let generatedWallpapers = generateWallpapers(highlightForDisplay, backgroundURL, targets)
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

            appliedGeneratedWallpapers = generatedWallpapers
        } else {
            do {
                let wallpaperURL = context.generateWallpaper(highlightForDisplay, backgroundURL)
                try context.setWallpaper(wallpaperURL)
                appliedGeneratedWallpapers = [
                    GeneratedWallpaper(
                        targetIdentifier: StoredGeneratedWallpaper.allScreensTargetIdentifier,
                        fileURL: wallpaperURL
                    )
                ]
            } catch {
                return RotationExecution(
                    outcome: .wallpaperApplyFailure(.applyError),
                    currentQuotePreview: nil,
                    lastChangedAt: nil
                )
            }
        }

        context.storeReusableGeneratedWallpapers(appliedGeneratedWallpapers)
        context.markHighlightShown(highlight.id)
        let changedAt = context.now()
        context.setLastChangedAt(changedAt)
        return RotationExecution(
            outcome: .success,
            currentQuotePreview: displayQuoteText,
            lastChangedAt: changedAt
        )
    }

    nonisolated private static func displayHighlight(_ highlight: Highlight, quoteText: String) -> Highlight {
        Highlight(
            id: highlight.id,
            bookId: highlight.bookId,
            quoteText: quoteText,
            bookTitle: highlight.bookTitle,
            author: highlight.author,
            location: highlight.location,
            dateAdded: highlight.dateAdded,
            lastShownAt: highlight.lastShownAt,
            isEnabled: highlight.isEnabled
        )
    }

    nonisolated private static func transformedQuoteTextForDisplay(
        _ quoteText: String,
        capitalizeFirstLetterIfLowercase: Bool
    ) -> String {
        guard capitalizeFirstLetterIfLowercase else {
            return quoteText
        }

        guard let firstLetterRange = firstLetterRange(in: quoteText) else {
            return quoteText
        }

        let firstLetter = quoteText[firstLetterRange]
        let firstLetterString = String(firstLetter)
        let lowercase = firstLetterString.lowercased()
        let uppercase = firstLetterString.uppercased()

        guard firstLetterString == lowercase, firstLetterString != uppercase else {
            return quoteText
        }

        var transformed = quoteText
        transformed.replaceSubrange(firstLetterRange, with: uppercase)
        return transformed
    }

    nonisolated private static func firstLetterRange(in text: String) -> Range<String.Index>? {
        for index in text.indices {
            let nextIndex = text.index(after: index)
            let characterRange = index..<nextIndex
            let character = String(text[characterRange])
            if character.rangeOfCharacter(from: .letters) != nil {
                return characterRange
            }
        }
        return nil
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
        capitalizeHighlightText = userDefaults.capitalizeHighlightText
    }

    func refreshAllState() {
        refreshLibraryState()
        refreshScheduleState()
    }

    func loadBackgroundPreviewState() -> BackgroundPreviewState {
        loadBackgroundPreviewStateAction()
    }

    func saveBackgroundImageSelection(from sourceURL: URL) throws {
        try saveBackgroundImageSelectionAction(sourceURL)
    }

    func loadBackgroundCollectionState() -> BackgroundCollectionState {
        loadBackgroundCollectionStateAction()
    }

    func addBackgroundImageSelection(from sourceURL: URL) throws {
        try addBackgroundImageSelectionAction(sourceURL)
    }

    func removeBackgroundImageSelection(id: UUID) throws {
        try removeBackgroundImageSelectionAction(id)
    }

    func setPrimaryBackgroundImageSelection(id: UUID) throws {
        try setPrimaryBackgroundImageSelectionAction(id)
    }

    func setActiveScheduleMode(_ mode: RotationScheduleMode) {
        userDefaults.rotationScheduleMode = mode
        activeScheduleMode = mode
    }

    func setCapitalizeHighlightText(_ enabled: Bool) {
        userDefaults.capitalizeHighlightText = enabled
        capitalizeHighlightText = enabled
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
    private static func warningMessage(from outcome: BackgroundImageStore.LoadCollectionOutcome) -> String? {
        switch outcome {
        case .success, .empty:
            return nil
        case .partiallyRecovered(let removedInvalidEntries):
            let noun = removedInvalidEntries == 1 ? "entry" : "entries"
            return "Recovered background collection by removing \(removedInvalidEntries) invalid \(noun)."
        case .migrationFailed(let reason):
            return reason.message
        }
    }

    static func live(userDefaults: UserDefaults = .standard) -> AppState {
        let backgroundStore = BackgroundImageStore(userDefaults: userDefaults)
        let wallpaperGenerator = WallpaperGenerator(
            protectedGeneratedWallpapersProvider: {
                userDefaults.loadReusableGeneratedWallpapers().map(\.fileURL)
            }
        )

        return AppState(
            userDefaults: userDefaults,
            pickNextHighlight: DatabaseManager.pickNextHighlight,
            loadBackgroundImageURLs: backgroundStore.loadBackgroundImageURLs,
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
            storeReusableGeneratedWallpapers: { generatedWallpapers in
                userDefaults.storeReusableGeneratedWallpapers(
                    generatedWallpapers.map { wallpaper in
                        StoredGeneratedWallpaper(
                            targetIdentifier: wallpaper.targetIdentifier,
                            fileURL: wallpaper.fileURL
                        )
                    }
                )
            },
            reapplyStoredWallpaper: {
                let storedWallpapers = userDefaults.loadReusableGeneratedWallpapers()
                guard !storedWallpapers.isEmpty else {
                    return false
                }

                let resolvedScreens = WallpaperSetter.resolvedConnectedScreens()
                return (try? WallpaperSetter.tryReapplyStoredWallpapers(
                    storedWallpapers,
                    on: resolvedScreens
                )) ?? false
            },
            markHighlightShown: DatabaseManager.markHighlightShown(id:),
            setBookEnabled: DatabaseManager.setBookEnabled(id:enabled:),
            setAllBooksEnabled: DatabaseManager.setAllBooksEnabled(enabled:),
            fetchAllBooks: DatabaseManager.fetchAllBooks,
            fetchTotalHighlightCount: DatabaseManager.totalHighlightCount,
            loadBackgroundPreviewState: {
                let result = backgroundStore.loadBackgroundImageCollection()
                return BackgroundPreviewState(
                    primaryImageURL: result.items.first(where: { $0.id == result.selectedItemID })?.fileURL,
                    warningMessage: warningMessage(from: result.outcome)
                )
            },
            saveBackgroundImageSelection: { sourceURL in
                _ = try backgroundStore.saveBackgroundImage(from: sourceURL)
            },
            loadBackgroundCollectionState: {
                let result = backgroundStore.loadBackgroundImageCollection()
                return BackgroundCollectionState(
                    items: result.items.map { item in
                        BackgroundCollectionItem(
                            id: item.id,
                            fileURL: item.fileURL,
                            addedAt: item.addedAt
                        )
                    },
                    selectedItemID: result.selectedItemID,
                    warningMessage: warningMessage(from: result.outcome)
                )
            },
            addBackgroundImageSelection: { sourceURL in
                _ = try backgroundStore.addBackgroundImage(from: sourceURL)
            },
            removeBackgroundImageSelection: { id in
                _ = try backgroundStore.removeBackgroundImage(id: id)
            },
            setPrimaryBackgroundImageSelection: { id in
                _ = try backgroundStore.promoteBackgroundImage(id: id)
            }
        )
    }
}
#endif
