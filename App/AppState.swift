import Combine
import Dispatch
import Foundation
#if canImport(AppKit)
import AppKit
#endif

private let wallpaperRotationQueue = DispatchQueue(
    label: "KindleWall.AppState.WallpaperRotation",
    qos: .userInitiated
)

private let quotesQueryWorkQueue = DispatchQueue(
    label: "KindleWall.QuotesQueryService",
    qos: .userInitiated,
    attributes: .concurrent
)

#if !canImport(GRDB)
struct QuotesPagePayload: Equatable {
    let highlights: [Highlight]
    let totalMatchingHighlightCount: Int
}

struct QuotesFilterOptionsPayload: Equatable {
    let availableBookTitles: [String]
    let availableAuthors: [String]
}
#endif

struct QuotesQuerySnapshot: Equatable {
    let highlights: [Highlight]
    let totalMatchingHighlightCount: Int
    let availableBookTitles: [String]
    let availableAuthors: [String]
}

final class QuotesQueryService {
    typealias FetchPagePayload = (String, QuotesListFilters, QuotesListSortMode, Int, Int) -> QuotesPagePayload
    typealias FetchFilterOptions = (String, QuotesListFilters) -> QuotesFilterOptionsPayload
    typealias FetchHighlightsPage = (String, QuotesListFilters, QuotesListSortMode, Int, Int) -> [Highlight]

    private let fetchPagePayload: FetchPagePayload
    private let fetchFilterOptions: FetchFilterOptions
    private let fetchHighlightsPage: FetchHighlightsPage

    init(
        fetchPagePayload: @escaping FetchPagePayload,
        fetchFilterOptions: @escaping FetchFilterOptions,
        fetchHighlightsPage: @escaping FetchHighlightsPage
    ) {
        self.fetchPagePayload = fetchPagePayload
        self.fetchFilterOptions = fetchFilterOptions
        self.fetchHighlightsPage = fetchHighlightsPage
    }

    convenience init(
        fetchHighlightsPage: @escaping FetchHighlightsPage,
        countHighlights: @escaping (String, QuotesListFilters) -> Int,
        fetchAvailableHighlightBookTitles: @escaping (String, QuotesListFilters) -> [String],
        fetchAvailableHighlightAuthors: @escaping (String, QuotesListFilters) -> [String]
    ) {
        self.init(
            fetchPagePayload: { searchText, filters, sortMode, limit, offset in
                QuotesPagePayload(
                    highlights: fetchHighlightsPage(searchText, filters, sortMode, limit, offset),
                    totalMatchingHighlightCount: countHighlights(searchText, filters)
                )
            },
            fetchFilterOptions: { searchText, filters in
                QuotesFilterOptionsPayload(
                    availableBookTitles: fetchAvailableHighlightBookTitles(searchText, filters),
                    availableAuthors: fetchAvailableHighlightAuthors(searchText, filters)
                )
            },
            fetchHighlightsPage: fetchHighlightsPage
        )
    }

    func loadPagePayload(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters(),
        sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded,
        pageSize: Int
    ) async -> QuotesPagePayload {
        let fetchPagePayload = self.fetchPagePayload
        return await Self.executeQuery {
            fetchPagePayload(searchText, filters, sortMode, pageSize, 0)
        }
    }

    func loadFilterOptions(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) async -> QuotesFilterOptionsPayload {
        let fetchFilterOptions = self.fetchFilterOptions
        return await Self.executeQuery {
            fetchFilterOptions(searchText, filters)
        }
    }

    func loadSnapshot(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters(),
        sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded,
        pageSize: Int
    ) async -> QuotesQuerySnapshot {
        async let pagePayload = loadPagePayload(
            searchText: searchText,
            filters: filters,
            sortedBy: sortMode,
            pageSize: pageSize
        )
        async let filterOptions = loadFilterOptions(
            searchText: searchText,
            filters: filters
        )

        let loadedPagePayload = await pagePayload
        let loadedFilterOptions = await filterOptions

        return QuotesQuerySnapshot(
            highlights: loadedPagePayload.highlights,
            totalMatchingHighlightCount: loadedPagePayload.totalMatchingHighlightCount,
            availableBookTitles: loadedFilterOptions.availableBookTitles,
            availableAuthors: loadedFilterOptions.availableAuthors
        )
    }

    func loadPage(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters(),
        sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded,
        limit: Int,
        offset: Int
    ) async -> [Highlight] {
        let fetchHighlightsPage = self.fetchHighlightsPage
        return await Self.executeQuery {
            fetchHighlightsPage(searchText, filters, sortMode, limit, offset)
        }
    }

    private static func executeQuery<T>(
        _ work: @escaping () -> T
    ) async -> T {
        await withCheckedContinuation { continuation in
            let workItem = DispatchWorkItem {
                continuation.resume(returning: work())
            }
            quotesQueryWorkQueue.async(execute: workItem)
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    enum QuoteSaveError: Error, Equatable, LocalizedError {
        case duplicateQuote

        var errorDescription: String? {
            switch self {
            case .duplicateQuote:
                return "A matching quote already exists in your library."
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .duplicateQuote:
                return "Edit the quote details or cancel to keep the original saved quote unchanged."
            }
        }
    }

    struct WallpaperTarget: Equatable {
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
        let backingScaleFactor: CGFloat
        let originX: Int?
        let originY: Int?

        init(
            identifier: String,
            pixelWidth: Int,
            pixelHeight: Int,
            backingScaleFactor: CGFloat,
            originX: Int? = nil,
            originY: Int? = nil
        ) {
            self.identifier = identifier
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.backingScaleFactor = backingScaleFactor
            self.originX = originX
            self.originY = originY
        }
    }

    struct GeneratedWallpaper: Equatable {
        let targetIdentifier: String
        let fileURL: URL
        let pixelWidth: Int?
        let pixelHeight: Int?
        let backingScaleFactor: Double?
        let originX: Int?
        let originY: Int?

        init(
            targetIdentifier: String,
            fileURL: URL,
            pixelWidth: Int? = nil,
            pixelHeight: Int? = nil,
            backingScaleFactor: Double? = nil,
            originX: Int? = nil,
            originY: Int? = nil
        ) {
            self.targetIdentifier = targetIdentifier
            self.fileURL = fileURL
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.backingScaleFactor = backingScaleFactor
            self.originX = originX
            self.originY = originY
        }
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

    struct ImportStatus: Equatable {
        let message: String
        let isError: Bool
        let warningDetails: [String]

        init(
            message: String = "",
            isError: Bool = false,
            warningDetails: [String] = []
        ) {
            let normalizedMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedWarningDetails = warningDetails
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            self.message = normalizedMessage
            self.isError = isError
            self.warningDetails = normalizedWarningDetails
        }

        var statusMessage: String {
            isError ? "" : message
        }

        var errorMessage: String? {
            guard isError else {
                return nil
            }

            return message.isEmpty ? "Import failed: unknown error." : message
        }
    }

    enum WallpaperApplyFailureReason: Equatable {
        case noTargets
        case generatedTargetMismatch
        case applyError
    }

    enum TopologyWallpaperReapplyOutcome: Equatable {
        case reapplied
        case alreadyApplied
        case noConnectedScreens
        case noCurrentWallpaper
        case applyFailure
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

    struct StoredWallpaperAssignmentPersistence {
        let load: () -> [StoredGeneratedWallpaper]
        let replace: ([GeneratedWallpaper]) -> Void
        let merge: ([GeneratedWallpaper]) -> Void
        let clear: () -> Void

        static let noOp = StoredWallpaperAssignmentPersistence(
            load: { [] },
            replace: { _ in },
            merge: { _ in },
            clear: {}
        )
    }

    typealias WallpaperRestoreOutcome = WallpaperSetter.RestoreOutcome
    typealias PickNextHighlight = () -> Highlight?
    typealias LoadBackgroundImageURLs = () -> [URL]
    typealias LoadBackgroundImageURL = () -> URL?
    typealias SelectBackgroundImageURL = ([URL]) -> URL?
    typealias GenerateWallpaper = (Highlight, URL?) -> URL
    typealias SetWallpaper = (URL) throws -> Void
    typealias PrepareWallpaperRotation = () -> WallpaperRotationPlan?
    typealias GenerateWallpapers = (Highlight, URL?, [WallpaperTarget]) -> [GeneratedWallpaper]
    typealias ReapplyStoredWallpaper = () -> WallpaperRestoreOutcome
    typealias ReapplyCurrentWallpaperForTopology = () -> TopologyWallpaperReapplyOutcome
    typealias MarkHighlightShown = (UUID) -> Void
    typealias InsertHighlight = (Highlight) -> Void
    typealias UpdateHighlight = (Highlight) throws -> Void
    typealias DeleteHighlight = (UUID) -> Void
    typealias DeleteHighlights = ([UUID]) -> LibrarySnapshot
    typealias PrepareBulkBookDeletion = ([UUID]) -> BulkBookDeletionPlan
    typealias DeleteBooks = (BulkBookDeletionPlan) -> LibrarySnapshot
    typealias SetBookEnabled = (UUID, Bool) -> Void
    typealias SetAllBooksEnabled = (Bool) -> Void
    typealias SetHighlightEnabled = (UUID, Bool) -> Void
    typealias FetchAllBooks = () -> [Book]
    typealias FetchAllHighlights = (QuotesListSortMode) -> [Highlight]
    typealias FetchHighlightsPage = (String, QuotesListFilters, QuotesListSortMode, Int, Int) -> [Highlight]
    typealias CountHighlights = (String, QuotesListFilters) -> Int
    typealias FetchAvailableHighlightBookTitles = (String, QuotesListFilters) -> [String]
    typealias FetchAvailableHighlightAuthors = (String, QuotesListFilters) -> [String]
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
    @Published private(set) var latestImportStatus: ImportStatus
    @Published private(set) var totalHighlightCount: Int
    @Published private(set) var books: [Book]
    @Published private(set) var isBookMutationInFlight: Bool
    @Published private(set) var activeScheduleMode: RotationScheduleMode
    @Published private(set) var lastChangedAt: Date?
    @Published private(set) var capitalizeHighlightText: Bool
    let quotesQueryService: QuotesQueryService

    private let userDefaults: UserDefaults
    private let pickNextHighlight: PickNextHighlight
    private let loadBackgroundImageURLs: LoadBackgroundImageURLs
    private let selectBackgroundImageURL: SelectBackgroundImageURL
    private let generateWallpaper: GenerateWallpaper
    private let setWallpaper: SetWallpaper
    private let prepareWallpaperRotation: PrepareWallpaperRotation?
    private let generateWallpapers: GenerateWallpapers?
    private let storedWallpaperAssignmentPersistence: StoredWallpaperAssignmentPersistence
    private let reapplyStoredWallpaper: ReapplyStoredWallpaper
    private let reapplyCurrentWallpaperForTopology: ReapplyCurrentWallpaperForTopology
    private let markHighlightShown: MarkHighlightShown
    private let insertHighlightAction: InsertHighlight
    private let updateHighlightAction: UpdateHighlight
    private let deleteHighlightsAction: DeleteHighlights
    private let prepareBulkBookDeletionAction: PrepareBulkBookDeletion
    private let deleteBooksAction: DeleteBooks
    private let setBookEnabledAction: SetBookEnabled
    private let setAllBooksEnabledAction: SetAllBooksEnabled
    private let setHighlightEnabledAction: SetHighlightEnabled
    private let fetchAllBooks: FetchAllBooks
    private let fetchAllHighlights: FetchAllHighlights
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

    var importStatus: String {
        latestImportStatus.statusMessage
    }

    var importError: String? {
        latestImportStatus.errorMessage
    }

    var importWarningDetails: [String] {
        latestImportStatus.warningDetails
    }

    nonisolated private static func enqueueRotationWork(_ work: @escaping () -> Void) {
        let workItem = DispatchWorkItem(block: work)
        wallpaperRotationQueue.async(execute: workItem)
    }

    nonisolated private static func deliverRotationResultOnMain(_ work: @escaping () -> Void) {
        let workItem = DispatchWorkItem(block: work)
        DispatchQueue.main.async(execute: workItem)
    }

    init(
        userDefaults: UserDefaults = .standard,
        currentQuotePreview: String = "",
        importStatus: ImportStatus = ImportStatus(),
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
        storedWallpaperAssignmentPersistence: StoredWallpaperAssignmentPersistence = .noOp,
        reapplyStoredWallpaper: @escaping ReapplyStoredWallpaper = { .noStoredWallpapers },
        reapplyCurrentWallpaperForTopology: @escaping ReapplyCurrentWallpaperForTopology = { .noCurrentWallpaper },
        markHighlightShown: @escaping MarkHighlightShown,
        insertHighlight: @escaping InsertHighlight = { _ in },
        updateHighlight: @escaping UpdateHighlight = { _ in },
        deleteHighlight: @escaping DeleteHighlight = { _ in },
        deleteHighlights: DeleteHighlights? = nil,
        prepareBulkBookDeletion: @escaping PrepareBulkBookDeletion = { _ in
            BulkBookDeletionPlan(bookIDs: [], linkedHighlights: [])
        },
        deleteBooks: DeleteBooks? = nil,
        setBookEnabled: @escaping SetBookEnabled = { _, _ in },
        setAllBooksEnabled: @escaping SetAllBooksEnabled = { _ in },
        setHighlightEnabled: @escaping SetHighlightEnabled = { _, _ in },
        fetchAllBooks: @escaping FetchAllBooks = { [] },
        fetchAllHighlights: @escaping FetchAllHighlights = { _ in [] },
        fetchHighlightsPage: @escaping FetchHighlightsPage = { _, _, _, _, _ in [] },
        countHighlights: @escaping CountHighlights = { _, _ in 0 },
        fetchAvailableHighlightBookTitles: @escaping FetchAvailableHighlightBookTitles = { _, _ in [] },
        fetchAvailableHighlightAuthors: @escaping FetchAvailableHighlightAuthors = { _, _ in [] },
        quotesQueryService: QuotesQueryService? = nil,
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

        let resolvedQuotesQueryService: QuotesQueryService
        if let quotesQueryService {
            resolvedQuotesQueryService = quotesQueryService
        } else {
            resolvedQuotesQueryService = QuotesQueryService(
                fetchHighlightsPage: fetchHighlightsPage,
                countHighlights: countHighlights,
                fetchAvailableHighlightBookTitles: fetchAvailableHighlightBookTitles,
                fetchAvailableHighlightAuthors: fetchAvailableHighlightAuthors
            )
        }

        self.userDefaults = userDefaults
        self.currentQuotePreview = currentQuotePreview
        self.latestImportStatus = importStatus
        self.totalHighlightCount = totalHighlightCount ?? fetchTotalHighlightCount()
        self.books = books ?? fetchAllBooks()
        self.isBookMutationInFlight = false
        self.activeScheduleMode = activeScheduleMode ?? userDefaults.rotationScheduleMode
        self.lastChangedAt = userDefaults.lastChangedAt
        self.capitalizeHighlightText = userDefaults.capitalizeHighlightText
        self.quotesQueryService = resolvedQuotesQueryService
        self.pickNextHighlight = pickNextHighlight
        self.loadBackgroundImageURLs = resolvedLoadBackgroundImageURLs
        self.selectBackgroundImageURL = resolvedSelectBackgroundImageURL
        self.generateWallpaper = generateWallpaper
        self.setWallpaper = setWallpaper
        self.prepareWallpaperRotation = prepareWallpaperRotation
        self.generateWallpapers = generateWallpapers
        self.storedWallpaperAssignmentPersistence = storedWallpaperAssignmentPersistence
        self.reapplyStoredWallpaper = reapplyStoredWallpaper
        self.reapplyCurrentWallpaperForTopology = reapplyCurrentWallpaperForTopology
        self.markHighlightShown = markHighlightShown
        self.insertHighlightAction = insertHighlight
        self.updateHighlightAction = updateHighlight
        if let deleteHighlights {
            self.deleteHighlightsAction = deleteHighlights
        } else {
            self.deleteHighlightsAction = { ids in
                ids.forEach(deleteHighlight)
                return LibrarySnapshot(
                    totalHighlightCount: fetchTotalHighlightCount(),
                    books: fetchAllBooks()
                )
            }
        }
        self.prepareBulkBookDeletionAction = prepareBulkBookDeletion
        if let deleteBooks {
            self.deleteBooksAction = deleteBooks
        } else {
            self.deleteBooksAction = { _ in
                LibrarySnapshot(
                    totalHighlightCount: fetchTotalHighlightCount(),
                    books: fetchAllBooks()
                )
            }
        }
        self.setBookEnabledAction = setBookEnabled
        self.setAllBooksEnabledAction = setAllBooksEnabled
        self.setHighlightEnabledAction = setHighlightEnabled
        self.fetchAllBooks = fetchAllBooks
        self.fetchAllHighlights = fetchAllHighlights
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
    func rotateWallpaper(forcedHighlight: Highlight? = nil) -> Bool {
        rotateWallpaperWithOutcome(forcedHighlight: forcedHighlight).didRotate
    }

    @discardableResult
    func requestWallpaperRotation(forcedHighlight: Highlight? = nil) -> Bool {
        guard !isRotationInProgress else {
            return false
        }

        isRotationInProgress = true
        let context = makeRotationPipelineContext(forcedHighlight: forcedHighlight)
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

    nonisolated func requestWallpaperRotationSynchronously(forcedHighlight: Highlight? = nil) -> Bool {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                requestWallpaperRotation(forcedHighlight: forcedHighlight)
            }
        }

        return DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                requestWallpaperRotation(forcedHighlight: forcedHighlight)
            }
        }
    }

    @discardableResult
    func rotateWallpaperWithOutcome(forcedHighlight: Highlight? = nil) -> WallpaperRotationOutcome {
        guard !isRotationInProgress else {
            return .alreadyInProgress
        }

        isRotationInProgress = true
        defer {
            isRotationInProgress = false
        }

        let execution = AppState.runWallpaperRotationPipeline(
            using: makeRotationPipelineContext(forcedHighlight: forcedHighlight)
        )
        publishRotationExecution(execution)
        return execution.outcome
    }

    @discardableResult
    func reapplyStoredWallpaperIfAvailable() -> WallpaperRestoreOutcome {
        reapplyStoredWallpaper()
    }

    @discardableResult
    func reapplyCurrentWallpaperForTopologyChange() -> TopologyWallpaperReapplyOutcome {
        reapplyCurrentWallpaperForTopology()
    }

    func replaceStoredWallpaperAssignments(_ wallpapers: [GeneratedWallpaper]) {
        storedWallpaperAssignmentPersistence.replace(wallpapers)
    }

    func mergeStoredWallpaperAssignments(_ wallpapers: [GeneratedWallpaper]) {
        storedWallpaperAssignmentPersistence.merge(wallpapers)
    }

    func clearStoredWallpaperAssignments() {
        storedWallpaperAssignmentPersistence.clear()
    }

    private struct RotationPipelineContext {
        let selectHighlight: () -> Highlight?
        let loadBackgroundImageURLs: LoadBackgroundImageURLs
        let selectBackgroundImageURL: SelectBackgroundImageURL
        let transformQuoteTextForDisplay: (String) -> String
        let generateWallpaper: GenerateWallpaper
        let setWallpaper: SetWallpaper
        let prepareWallpaperRotation: PrepareWallpaperRotation?
        let generateWallpapers: GenerateWallpapers?
        let persistAppliedWallpaperAssignments: ([GeneratedWallpaper]) -> Void
        let markHighlightShown: MarkHighlightShown
        let setLastChangedAt: (Date) -> Void
        let now: Now
    }

    private struct RotationExecution {
        let outcome: WallpaperRotationOutcome
        let currentQuotePreview: String?
        let lastChangedAt: Date?
    }

    private func makeRotationPipelineContext(forcedHighlight: Highlight? = nil) -> RotationPipelineContext {
        let capitalizeHighlightText = userDefaults.capitalizeHighlightText
        let resolvedForcedHighlight = forcedHighlight
        let pickNextHighlight = self.pickNextHighlight
        return RotationPipelineContext(
            selectHighlight: {
                resolvedForcedHighlight ?? pickNextHighlight()
            },
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
            persistAppliedWallpaperAssignments: { [self] wallpapers in
                self.persistAppliedWallpaperAssignments(wallpapers)
            },
            markHighlightShown: markHighlightShown,
            setLastChangedAt: { [userDefaults] changedAt in
                userDefaults.lastChangedAt = changedAt
            },
            now: now
        )
    }

    nonisolated private static func runWallpaperRotationPipeline(using context: RotationPipelineContext) -> RotationExecution {
        guard let highlight = context.selectHighlight() else {
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

        context.persistAppliedWallpaperAssignments(appliedGeneratedWallpapers)
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

    nonisolated static func reapplyCurrentWallpaperForTopology<Screen>(
        resolvedScreens: [WallpaperSetter.ResolvedScreen<Screen>],
        storedWallpapers: [StoredGeneratedWallpaper] = [],
        preferredSourceScreen: Screen?,
        sameScreen: (Screen, Screen) -> Bool,
        currentDesktopImageURL: @escaping WallpaperSetter.CurrentDesktopImageURL<Screen>,
        setDesktopImage: (URL, Screen) throws -> Void
    ) -> TopologyWallpaperReapplyOutcome {
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

    nonisolated private static func topologyWallpaperSourceURL<Screen>(
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

    nonisolated private static func topologyWallpaperSourceScreens<Screen>(
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

    private func persistAppliedWallpaperAssignments(_ wallpapers: [GeneratedWallpaper]) {
        if shouldMergePersistedWallpaperAssignments(with: wallpapers) {
            mergeStoredWallpaperAssignments(wallpapers)
            return
        }

        replaceStoredWallpaperAssignments(wallpapers)
    }

    private func shouldMergePersistedWallpaperAssignments(with wallpapers: [GeneratedWallpaper]) -> Bool {
        let newTargetedIdentifiers = Set(
            wallpapers.compactMap { wallpaper -> String? in
                guard wallpaper.targetIdentifier != StoredGeneratedWallpaper.allScreensTargetIdentifier else {
                    return nil
                }
                return wallpaper.targetIdentifier
            }
        )
        guard newTargetedIdentifiers.count == wallpapers.count else {
            return false
        }

        let storedTargetedIdentifiers = Set(
            storedWallpaperAssignmentPersistence.load().compactMap { wallpaper -> String? in
                guard wallpaper.targetIdentifier != StoredGeneratedWallpaper.allScreensTargetIdentifier else {
                    return nil
                }
                return wallpaper.targetIdentifier
            }
        )
        guard !storedTargetedIdentifiers.isEmpty else {
            return false
        }

        return newTargetedIdentifiers.count < storedTargetedIdentifiers.count
            && newTargetedIdentifiers.isSubset(of: storedTargetedIdentifiers)
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

    func setImportStatus(_ status: ImportStatus) {
        latestImportStatus = status
    }

    func setImportStatus(_ message: String, isError: Bool, warningDetails: [String] = []) {
        setImportStatus(
            ImportStatus(
                message: message,
                isError: isError,
                warningDetails: warningDetails
            )
        )
    }

    func refreshLibraryState() {
        applyLibrarySnapshot(
            LibrarySnapshot(
                totalHighlightCount: fetchTotalHighlightCount(),
                books: fetchAllBooks()
            )
        )
    }

    func loadAllHighlights(sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded) -> [Highlight] {
        fetchAllHighlights(sortMode)
    }

    func loadHighlight(id: UUID) -> Highlight? {
        fetchAllHighlights(.mostRecentlyAdded).first(where: { $0.id == id })
    }

    func addManualQuote(_ request: QuoteEditSaveRequest) {
        insertHighlightAction(
            Highlight(
                id: UUID(),
                bookId: request.bookId,
                quoteText: request.quoteText,
                bookTitle: request.bookTitle,
                author: request.author,
                location: request.location,
                dateAdded: now(),
                lastShownAt: nil,
                isEnabled: true
            )
        )
        refreshLibraryState()
    }

    @discardableResult
    func updateQuote(_ highlight: Highlight, with request: QuoteEditSaveRequest) throws -> Highlight {
        let updatedHighlight = Highlight(
            id: highlight.id,
            bookId: request.bookId,
            quoteText: request.quoteText,
            bookTitle: request.bookTitle,
            author: request.author,
            location: request.location,
            dateAdded: highlight.dateAdded,
            lastShownAt: highlight.lastShownAt,
            isEnabled: highlight.isEnabled
        )
        try updateHighlightAction(updatedHighlight)
        refreshLibraryState()
        return updatedHighlight
    }

    func deleteHighlight(id: UUID) {
        deleteHighlights(ids: [id])
    }

    func deleteHighlights(ids: [UUID]) {
        applyLibrarySnapshot(deleteHighlightsAction(ids))
    }

    @discardableResult
    func prepareBulkBookDeletion(bookIDs: [UUID]) -> BulkBookDeletionPlan {
        prepareBulkBookDeletionAction(bookIDs)
    }

    func deleteBooks(using plan: BulkBookDeletionPlan) {
        performBookMutationUsingSnapshot {
            guard !plan.bookIDs.isEmpty else {
                return nil
            }

            return deleteBooksAction(plan)
        }
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

    func setHighlightEnabled(id: UUID, enabled: Bool) {
        setHighlightEnabledAction(id, enabled)
        refreshLibraryState()
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

    func applyLibrarySnapshot(_ snapshot: LibrarySnapshot) {
        totalHighlightCount = snapshot.totalHighlightCount
        books = snapshot.books
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

    private func performBookMutationUsingSnapshot(_ mutation: () -> LibrarySnapshot?) {
        bookMutationLock.lock()
        isBookMutationInFlight = true
        defer {
            isBookMutationInFlight = false
            bookMutationLock.unlock()
        }

        guard let snapshot = mutation() else {
            return
        }
        applyLibrarySnapshot(snapshot)
    }
}

#if canImport(GRDB)
extension AppState {
    private static func storedGeneratedWallpapers(from wallpapers: [GeneratedWallpaper]) -> [StoredGeneratedWallpaper] {
        wallpapers.map { wallpaper in
            StoredGeneratedWallpaper(
                targetIdentifier: wallpaper.targetIdentifier,
                fileURL: wallpaper.fileURL,
                pixelWidth: wallpaper.pixelWidth,
                pixelHeight: wallpaper.pixelHeight,
                backingScaleFactor: wallpaper.backingScaleFactor,
                originX: wallpaper.originX,
                originY: wallpaper.originY
            )
        }
    }

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
                let resolvedScreens = DisplayIdentityResolver.resolvedConnectedScreens()
                guard !resolvedScreens.isEmpty else {
                    return nil
                }
                let targets = resolvedScreens.map { screen in
                    WallpaperTarget(
                        identifier: screen.identifier,
                        pixelWidth: screen.pixelWidth,
                        pixelHeight: screen.pixelHeight,
                        backingScaleFactor: screen.backingScaleFactor,
                        originX: screen.originX,
                        originY: screen.originY
                    )
                }
                return WallpaperRotationPlan(targets: targets) { generatedWallpapers in
                    let assignments = generatedWallpapers.map { generated in
                        WallpaperSetter.WallpaperAssignment(
                            screenIdentifier: generated.targetIdentifier,
                            imageURL: generated.fileURL
                        )
                    }
                    try WallpaperSetter.applyWallpapers(
                        assignments: assignments,
                        resolvedScreens: resolvedScreens,
                        currentDesktopImageURL: { screen in
                            NSWorkspace.shared.desktopImageURL(for: screen)
                        },
                        setDesktopImage: { url, screen in
                            try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                        }
                    )
                }
            },
            generateWallpapers: { highlight, backgroundURL, targets in
                let targetsByIdentifier = Dictionary(
                    uniqueKeysWithValues: targets.map { target in
                        (target.identifier, target)
                    }
                )
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
                    let target = targetsByIdentifier[generated.targetIdentifier]
                    return GeneratedWallpaper(
                        targetIdentifier: generated.targetIdentifier,
                        fileURL: generated.fileURL,
                        pixelWidth: target?.pixelWidth,
                        pixelHeight: target?.pixelHeight,
                        backingScaleFactor: target.map { Double($0.backingScaleFactor) },
                        originX: target?.originX,
                        originY: target?.originY
                    )
                }
            },
            storedWallpaperAssignmentPersistence: StoredWallpaperAssignmentPersistence(
                load: {
                    userDefaults.loadReusableGeneratedWallpapers()
                },
                replace: { generatedWallpapers in
                    userDefaults.replaceReusableGeneratedWallpapers(
                        Self.storedGeneratedWallpapers(from: generatedWallpapers)
                    )
                },
                merge: { generatedWallpapers in
                    userDefaults.mergeReusableGeneratedWallpapers(
                        Self.storedGeneratedWallpapers(from: generatedWallpapers)
                    )
                },
                clear: {
                    userDefaults.clearReusableGeneratedWallpapers()
                }
            ),
            reapplyStoredWallpaper: {
                let storedWallpapers = userDefaults.loadReusableGeneratedWallpapers()
                guard !storedWallpapers.isEmpty else {
                    return .noStoredWallpapers
                }

                return DisplayIdentityResolver.restoreStoredWallpapers(
                    storedWallpapers,
                    resolvedScreens: DisplayIdentityResolver.resolvedConnectedScreens(),
                    currentDesktopImageURL: { screen in
                        NSWorkspace.shared.desktopImageURL(for: screen)
                    },
                    setDesktopImage: { url, screen in
                        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    }
                )
            },
            reapplyCurrentWallpaperForTopology: {
                let resolvedScreens = DisplayIdentityResolver.resolvedConnectedScreens()
                let storedWallpapers = userDefaults.loadReusableGeneratedWallpapers()
                return AppState.reapplyCurrentWallpaperForTopology(
                    resolvedScreens: resolvedScreens,
                    storedWallpapers: storedWallpapers,
                    preferredSourceScreen: NSScreen.main,
                    sameScreen: { lhs, rhs in lhs === rhs },
                    currentDesktopImageURL: { screen in
                        NSWorkspace.shared.desktopImageURL(for: screen)
                    },
                    setDesktopImage: { url, screen in
                        try NSWorkspace.shared.setDesktopImageURL(url, for: screen, options: [:])
                    }
                )
            },
            markHighlightShown: DatabaseManager.markHighlightShown(id:),
            insertHighlight: DatabaseManager.insertHighlightIfNew(_:),
            updateHighlight: { highlight in
                do {
                    try DatabaseManager.updateHighlight(highlight)
                } catch DatabaseManager.HighlightUpdateError.duplicateDedupeKey {
                    throw QuoteSaveError.duplicateQuote
                }
            },
            deleteHighlights: DatabaseManager.deleteHighlights(ids:),
            prepareBulkBookDeletion: DatabaseManager.makeBulkBookDeletionPlan(bookIDs:),
            deleteBooks: DatabaseManager.deleteBooks(using:),
            setBookEnabled: DatabaseManager.setBookEnabled(id:enabled:),
            setAllBooksEnabled: DatabaseManager.setAllBooksEnabled(enabled:),
            setHighlightEnabled: DatabaseManager.setHighlightEnabled(id:enabled:),
            fetchAllBooks: DatabaseManager.fetchAllBooks,
            fetchAllHighlights: DatabaseManager.fetchAllHighlights,
            fetchHighlightsPage: DatabaseManager.fetchHighlightsPage(searchText:filters:sortedBy:limit:offset:),
            countHighlights: DatabaseManager.countHighlights(searchText:filters:),
            fetchAvailableHighlightBookTitles: DatabaseManager.fetchAvailableHighlightBookTitles(searchText:filters:),
            fetchAvailableHighlightAuthors: DatabaseManager.fetchAvailableHighlightAuthors(searchText:filters:),
            quotesQueryService: QuotesQueryService(
                fetchPagePayload: DatabaseManager.fetchHighlightPagePayload(searchText:filters:sortedBy:limit:offset:),
                fetchFilterOptions: DatabaseManager.fetchHighlightFilterOptions(searchText:filters:),
                fetchHighlightsPage: DatabaseManager.fetchHighlightsPage(searchText:filters:sortedBy:limit:offset:)
            ),
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
