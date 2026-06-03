import OSLog
import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

enum QuotesListSortMode: String, CaseIterable, Identifiable {
    case mostRecentlyAdded
    case alphabeticalByBook

    var id: Self { self }

    var title: String {
        switch self {
        case .mostRecentlyAdded:
            return "Most Recent"
        case .alphabeticalByBook:
            return "Book A-Z"
        }
    }
}

enum QuotesListBookStatusFilterMode: String, CaseIterable, Identifiable {
    case allBooks
    case enabledBooksOnly
    case disabledBooksOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .allBooks:
            return "All Books"
        case .enabledBooksOnly:
            return "Enabled Books"
        case .disabledBooksOnly:
            return "Disabled Books"
        }
    }
}

enum QuotesListSourceFilterMode: String, CaseIterable, Identifiable {
    case allQuotes
    case manualOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .allQuotes:
            return "All Quotes"
        case .manualOnly:
            return "Manual Only"
        }
    }
}

struct QuotesListFilters: Equatable {
    var selectedBookTitle: String?
    var selectedAuthor: String?
    var bookStatus: QuotesListBookStatusFilterMode = .allBooks
    var source: QuotesListSourceFilterMode = .allQuotes

    var isActive: Bool {
        selectedBookTitle != nil ||
        selectedAuthor != nil ||
        bookStatus != .allBooks ||
        source != .allQuotes
    }
}

enum QuotesListPresentationModel {
    static func displayedHighlights(
        from highlights: [Highlight],
        searchText: String,
        filters: QuotesListFilters,
        bookEnabledByID: [UUID: Bool]
    ) -> [Highlight] {
        highlights
            .filter { matchesFilters($0, filters: filters, bookEnabledByID: bookEnabledByID) }
            .filter { matchesSearch($0, searchText: searchText) }
    }

    static func sortedHighlights(
        _ highlights: [Highlight],
        sortMode: QuotesListSortMode
    ) -> [Highlight] {
        highlights.sorted { lhs, rhs in
            switch sortMode {
            case .mostRecentlyAdded:
                return compareByMostRecent(lhs, rhs)
            case .alphabeticalByBook:
                return compareAlphabetically(lhs, rhs)
            }
        }
    }

    static func availableBookTitles(from highlights: [Highlight]) -> [String] {
        uniqueSortedValues(from: highlights.map(bookTitleText(for:)))
    }

    static func availableAuthors(from highlights: [Highlight]) -> [String] {
        uniqueSortedValues(from: highlights.map(authorText(for:)))
    }

    static func previewText(for quoteText: String) -> String {
        let collapsedWhitespace = collapseWhitespace(in: quoteText)
        return collapsedWhitespace.isEmpty ? "Untitled quote" : collapsedWhitespace
    }

    static func bookTitleText(for highlight: Highlight) -> String {
        fallbackText(from: highlight.bookTitle, placeholder: "Unknown Book")
    }

    static func authorText(for highlight: Highlight) -> String {
        fallbackText(from: highlight.author, placeholder: "Unknown Author")
    }

    private static func matchesFilters(
        _ highlight: Highlight,
        filters: QuotesListFilters,
        bookEnabledByID: [UUID: Bool]
    ) -> Bool {
        if let selectedBookTitle = filters.selectedBookTitle,
           bookTitleText(for: highlight) != selectedBookTitle {
            return false
        }

        if let selectedAuthor = filters.selectedAuthor,
           authorText(for: highlight) != selectedAuthor {
            return false
        }

        switch filters.source {
        case .allQuotes:
            break
        case .manualOnly:
            guard highlight.bookId == nil else {
                return false
            }
        }

        switch filters.bookStatus {
        case .allBooks:
            return true
        case .enabledBooksOnly:
            return bookEnabledState(for: highlight, bookEnabledByID: bookEnabledByID) == true
        case .disabledBooksOnly:
            return bookEnabledState(for: highlight, bookEnabledByID: bookEnabledByID) == false
        }
    }

    private static func matchesSearch(_ highlight: Highlight, searchText: String) -> Bool {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            return true
        }

        let searchableFields = [
            previewText(for: highlight.quoteText),
            bookTitleText(for: highlight),
            authorText(for: highlight)
        ]

        return searchableFields.contains { field in
            field.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private static func compareByMostRecent(_ lhs: Highlight, _ rhs: Highlight) -> Bool {
        switch (lhs.dateAdded, rhs.dateAdded) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return compareAlphabetically(lhs, rhs)
        }
    }

    private static func compareAlphabetically(_ lhs: Highlight, _ rhs: Highlight) -> Bool {
        let lhsKey = [
            bookTitleText(for: lhs),
            authorText(for: lhs),
            previewText(for: lhs.quoteText)
        ]
        let rhsKey = [
            bookTitleText(for: rhs),
            authorText(for: rhs),
            previewText(for: rhs.quoteText)
        ]

        for (lhsValue, rhsValue) in zip(lhsKey, rhsKey) where lhsValue.caseInsensitiveCompare(rhsValue) != .orderedSame {
            return lhsValue.localizedCaseInsensitiveCompare(rhsValue) == .orderedAscending
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func fallbackText(from rawValue: String, placeholder: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }

    private static func collapseWhitespace(in string: String) -> String {
        string.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func uniqueSortedValues(from values: [String]) -> [String] {
        let sortedValues = values.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        var dedupedValues: [String] = []
        dedupedValues.reserveCapacity(sortedValues.count)

        for value in sortedValues {
            if dedupedValues.last?.localizedCaseInsensitiveCompare(value) == .orderedSame {
                continue
            }
            dedupedValues.append(value)
        }

        return dedupedValues
    }

    private static func bookEnabledState(
        for highlight: Highlight,
        bookEnabledByID: [UUID: Bool]
    ) -> Bool? {
        guard let bookId = highlight.bookId else {
            return nil
        }

        return bookEnabledByID[bookId]
    }
}

enum QuotesListPerformanceSignposts {
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.marcuslo.leaf",
        category: .pointsOfInterest
    )

    static func beginRefresh(reason: String, sortMode: QuotesListSortMode) -> OSSignpostIntervalState {
        signposter.beginInterval(
            "QuotesListRefresh",
            "reason=\(reason, privacy: .public) sortMode=\(sortMode.rawValue, privacy: .public)"
        )
    }

    static func endRefresh(_ state: OSSignpostIntervalState, loadedCount: Int) {
        signposter.endInterval(
            "QuotesListRefresh",
            state,
            "rows=\(loadedCount)"
        )
    }

    static func cancelRefresh(_ state: OSSignpostIntervalState) {
        signposter.endInterval(
            "QuotesListRefresh",
            state,
            "cancelled=1"
        )
    }

    static func beginRender(reason: String, sortMode: QuotesListSortMode, totalCount: Int) -> OSSignpostIntervalState {
        signposter.beginInterval(
            "QuotesListRender",
            "reason=\(reason, privacy: .public) sortMode=\(sortMode.rawValue, privacy: .public) total=\(totalCount)"
        )
    }

    static func endRender(_ state: OSSignpostIntervalState, displayedCount: Int) {
        signposter.endInterval(
            "QuotesListRender",
            state,
            "displayed=\(displayedCount)"
        )
    }

    static func cancelRender(_ state: OSSignpostIntervalState) {
        signposter.endInterval(
            "QuotesListRender",
            state,
            "cancelled=1"
        )
    }
}

enum QuotesListPagingConstants {
    static let pageSize = 100
    static let loadMoreThreshold = 20
}

enum QuotesListRefreshReason: String {
    case appear
    case refresh
    case sortChanged
    case searchChanged
    case bookFilterChanged
    case authorFilterChanged
    case bookStatusChanged
    case sourceFilterChanged
    case libraryChanged
}

enum QuotesListSearchPresentationModel {
    struct SearchRefreshCommitState: Equatable {
        let effectiveSearchText: String
        let shouldRefresh: Bool
    }

    struct RefreshQueryState: Equatable {
        let searchText: String
        let shouldCancelPendingSearchRefresh: Bool
    }

    static func hasActiveQuery(
        effectiveSearchText: String,
        filters: QuotesListFilters
    ) -> Bool {
        !effectiveSearchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filters.isActive
    }

    static func commitSearchRefresh(
        rawSearchText: String,
        effectiveSearchText: String
    ) -> SearchRefreshCommitState {
        SearchRefreshCommitState(
            effectiveSearchText: rawSearchText,
            shouldRefresh: rawSearchText != effectiveSearchText
        )
    }

    static func refreshQueryState(
        reason: QuotesListRefreshReason,
        effectiveSearchText: String,
        searchTextOverride: String? = nil
    ) -> RefreshQueryState {
        RefreshQueryState(
            searchText: searchTextOverride ?? effectiveSearchText,
            shouldCancelPendingSearchRefresh: reason == .searchChanged
        )
    }

    static func pagingSearchText(effectiveSearchText: String) -> String {
        effectiveSearchText
    }
}

enum QuotesListRefreshPresentationModel {
    static func reloadsFilterOptions(for reason: QuotesListRefreshReason) -> Bool {
        reason != .sortChanged
    }

    static func shouldAcceptAsyncResult(
        capturedGeneration: Int,
        activeQueryGeneration: Int
    ) -> Bool {
        capturedGeneration == activeQueryGeneration
    }
}

enum QuotesListPrimaryContent: String {
    case initialLoading
    case libraryEmpty
    case noMatchingResults
    case list
}

struct QuotesListContentPresentationState: Equatable {
    let primaryContent: QuotesListPrimaryContent
    let showsRefreshOverlay: Bool
}

struct QuotesFilterOverflowPresentationState: Equatable {
    let showsLeadingAffordance: Bool
    let showsTrailingAffordance: Bool
}

enum QuotesListContentPresentationModel {
    static func resolvedPrimaryContent(
        totalHighlightCount: Int,
        displayedRowCount: Int
    ) -> QuotesListPrimaryContent {
        if totalHighlightCount == 0 {
            return .libraryEmpty
        }

        if displayedRowCount == 0 {
            return .noMatchingResults
        }

        return .list
    }

    static func presentationState(
        isLoadingHighlights: Bool,
        lastResolvedPrimaryContent: QuotesListPrimaryContent?,
        totalHighlightCount: Int,
        displayedRowCount: Int
    ) -> QuotesListContentPresentationState {
        if isLoadingHighlights {
            if let lastResolvedPrimaryContent {
                return QuotesListContentPresentationState(
                    primaryContent: lastResolvedPrimaryContent,
                    showsRefreshOverlay: true
                )
            }

            return QuotesListContentPresentationState(
                primaryContent: .initialLoading,
                showsRefreshOverlay: false
            )
        }

        return QuotesListContentPresentationState(
            primaryContent: resolvedPrimaryContent(
                totalHighlightCount: totalHighlightCount,
                displayedRowCount: displayedRowCount
            ),
            showsRefreshOverlay: false
        )
    }
}

enum QuotesFilterOverflowPresentationModel {
    static func presentationState(
        viewportWidth: CGFloat,
        contentWidth: CGFloat,
        contentOffset: CGFloat,
        tolerance: CGFloat = 1
    ) -> QuotesFilterOverflowPresentationState {
        guard viewportWidth > 0, contentWidth - viewportWidth > tolerance else {
            return QuotesFilterOverflowPresentationState(
                showsLeadingAffordance: false,
                showsTrailingAffordance: false
            )
        }

        let maxOffset = max(contentWidth - viewportWidth, 0)
        let clampedOffset = min(max(contentOffset, 0), maxOffset)

        return QuotesFilterOverflowPresentationState(
            showsLeadingAffordance: clampedOffset > tolerance,
            showsTrailingAffordance: maxOffset - clampedOffset > tolerance
        )
    }
}

struct QuotesListRefreshResetState {
    let queryGeneration: Int
    let isLoadingHighlights: Bool
    let isLoadingNextPage: Bool
    let hasMoreHighlights: Bool
    let highlights: [Highlight]
    let totalMatchingHighlightCount: Int
    let availableBookTitles: [String]
    let availableAuthors: [String]
    let selectedHighlightIDs: Set<UUID>
}

struct QuotesListAppendPageResult {
    let highlights: [Highlight]
    let hasMoreHighlights: Bool
}

enum QuotesListPagingPresentationModel {
    static func refreshResetState(queryGeneration: Int) -> QuotesListRefreshResetState {
        refreshResetState(
            queryGeneration: queryGeneration,
            preservingHighlights: [],
            totalMatchingHighlightCount: 0,
            availableBookTitles: [],
            availableAuthors: [],
            selectedHighlightIDs: []
        )
    }

    static func refreshResetState(
        queryGeneration: Int,
        preservingHighlights: [Highlight],
        totalMatchingHighlightCount: Int,
        availableBookTitles: [String],
        availableAuthors: [String],
        selectedHighlightIDs: Set<UUID>
    ) -> QuotesListRefreshResetState {
        QuotesListRefreshResetState(
            queryGeneration: queryGeneration,
            isLoadingHighlights: true,
            isLoadingNextPage: false,
            hasMoreHighlights: false,
            highlights: preservingHighlights,
            totalMatchingHighlightCount: totalMatchingHighlightCount,
            availableBookTitles: availableBookTitles,
            availableAuthors: availableAuthors,
            selectedHighlightIDs: selectedHighlightIDs
        )
    }

    static func hasMoreHighlights(
        loadedCount: Int,
        totalMatchingHighlightCount: Int
    ) -> Bool {
        loadedCount < totalMatchingHighlightCount
    }

    static func shouldLoadMore(
        highlights: [Highlight],
        currentHighlightID: UUID,
        hasMoreHighlights: Bool,
        isLoadingHighlights: Bool,
        isLoadingNextPage: Bool,
        hasLoadMoreTask: Bool,
        loadMoreThreshold: Int = QuotesListPagingConstants.loadMoreThreshold
    ) -> Bool {
        guard
            hasMoreHighlights,
            !isLoadingHighlights,
            !isLoadingNextPage,
            !hasLoadMoreTask,
            let currentIndex = highlights.firstIndex(where: { $0.id == currentHighlightID })
        else {
            return false
        }

        let thresholdIndex = max(highlights.count - loadMoreThreshold, 0)
        return currentIndex >= thresholdIndex
    }

    static func appendPage(
        existingHighlights: [Highlight],
        nextPage: [Highlight],
        totalMatchingHighlightCount: Int
    ) -> QuotesListAppendPageResult {
        let existingHighlightIDs = Set(existingHighlights.map(\.id))
        let uniqueNextPage = nextPage.filter { !existingHighlightIDs.contains($0.id) }
        let mergedHighlights = existingHighlights + uniqueNextPage

        return QuotesListAppendPageResult(
            highlights: mergedHighlights,
            hasMoreHighlights: mergedHighlights.count < totalMatchingHighlightCount && !uniqueNextPage.isEmpty
        )
    }
}

@MainActor
final class QuotesListRuntimeState: ObservableObject {
    @Published private(set) var rowModels: [QuotesListRowModel] = []
    @Published var renderObservationToken = UUID()

    var highlights: [Highlight] = []
    var totalMatchingHighlightCount = 0
    var availableBookTitles: [String] = []
    var availableAuthors: [String] = []
    var isLoadingHighlights = false
    var isLoadingNextPage = false
    var hasMoreHighlights = false
    var lastResolvedPrimaryContent: QuotesListPrimaryContent? = nil
    var queryGeneration = 0
    var pendingSearchRefreshTask: Task<Void, Never>? = nil
    var refreshTask: Task<Void, Never>? = nil
    var loadMoreTask: Task<Void, Never>? = nil
    var pendingRefreshSignpostState: OSSignpostIntervalState? = nil
    var pendingRenderSignpostState: OSSignpostIntervalState? = nil

    func replaceRows(with highlights: [Highlight]) {
        let newRowModels = makeRowModels(from: highlights)
        guard newRowModels != rowModels else {
            return
        }

        rowModels = newRowModels
    }

    func clearRows() {
        guard !rowModels.isEmpty else {
            return
        }

        rowModels = []
    }

    func appendRows(from uniqueNextPage: [Highlight]) {
        rowModels.append(contentsOf: makeRowModels(from: uniqueNextPage))
    }

    private func makeRowModels(from highlights: [Highlight]) -> [QuotesListRowModel] {
        highlights.map(QuotesListRowModel.init)
    }
}

struct QuotesListControlsRow: View {
    private static let filterScrollCoordinateSpaceName = "QuotesFilterControlsScrollView"
    private static let searchFieldWidth: CGFloat = 420
    private static let searchFieldHeight: CGFloat = 30
    private static let sortPickerWidth: CGFloat = 240
    private static let resultSummaryWidth: CGFloat = 190
    private static let bookStatusFilterWidth: CGFloat = 220
    private static let sourceFilterWidth: CGFloat = 230

    let committedSearchText: String
    @Binding var sortMode: QuotesListSortMode
    @Binding var filters: QuotesListFilters
    let resultCountSummary: String
    @Binding var filterControlsViewportWidth: CGFloat
    @Binding var filterControlsContentWidth: CGFloat
    @Binding var filterControlsContentOffset: CGFloat
    let onSearchTextChanged: (String) -> Void

    var body: some View {
        let overflowPresentation = QuotesFilterOverflowPresentationModel.presentationState(
            viewportWidth: filterControlsViewportWidth,
            contentWidth: filterControlsContentWidth,
            contentOffset: filterControlsContentOffset
        )

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                QuotesLibrarySearchField(
                    committedSearchText: committedSearchText,
                    placeholder: "Search quotes, books, or authors",
                    onTextChanged: onSearchTextChanged
                )
                .frame(
                    width: Self.searchFieldWidth,
                    height: Self.searchFieldHeight,
                    alignment: .leading
                )

                Text("Sort")
                    .fixedSize(horizontal: true, vertical: false)

                Picker("Sort", selection: $sortMode) {
                    ForEach(QuotesListSortMode.allCases) { mode in
                        Text(mode.title)
                            .tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: Self.sortPickerWidth)

                Spacer(minLength: 12)

                Text(resultCountSummary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: Self.resultSummaryWidth, alignment: .trailing)
            }

            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .center, spacing: 12) {
                            Picker("Book Status", selection: $filters.bookStatus) {
                                ForEach(QuotesListBookStatusFilterMode.allCases) { mode in
                                    Text(mode.title)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: Self.bookStatusFilterWidth)

                            Picker("Manual Added", selection: $filters.source) {
                                ForEach(QuotesListSourceFilterMode.allCases) { mode in
                                    Text(mode.title)
                                        .tag(mode)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: Self.sourceFilterWidth)
                        }
                        .background(filterControlsContentMetricsReader)
                    }
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .coordinateSpace(name: Self.filterScrollCoordinateSpaceName)
                    .background(filterControlsViewportMetricsReader)
                    .overlay(alignment: .leading) {
                        overflowAffordanceOverlay(
                            systemImage: "chevron.left",
                            isVisible: overflowPresentation.showsLeadingAffordance,
                            alignment: .leading
                        )
                    }
                    .overlay(alignment: .trailing) {
                        overflowAffordanceOverlay(
                            systemImage: "chevron.right",
                            isVisible: overflowPresentation.showsTrailingAffordance,
                            alignment: .trailing
                        )
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if filters.isActive {
                    Button("Reset Filters") {
                        filters = QuotesListFilters()
                    }
                }
            }
        }
    }

    private var filterControlsViewportMetricsReader: some View {
        GeometryReader { geometry in
            Color.clear
                .preference(
                    key: QuotesFilterControlsViewportWidthPreferenceKey.self,
                    value: geometry.size.width
                )
        }
        .onPreferenceChange(QuotesFilterControlsViewportWidthPreferenceKey.self) { width in
            filterControlsViewportWidth = width
        }
    }

    private var filterControlsContentMetricsReader: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .named(Self.filterScrollCoordinateSpaceName))
            Color.clear
                .preference(
                    key: QuotesFilterControlsContentMetricsPreferenceKey.self,
                    value: QuotesFilterControlsContentMetrics(
                        width: frame.width,
                        minX: frame.minX
                    )
                )
        }
        .onPreferenceChange(QuotesFilterControlsContentMetricsPreferenceKey.self) { metrics in
            filterControlsContentWidth = metrics.width
            filterControlsContentOffset = max(-metrics.minX, 0)
        }
    }

    @ViewBuilder
    private func overflowAffordanceOverlay(
        systemImage: String,
        isVisible: Bool,
        alignment: Alignment
    ) -> some View {
        if isVisible {
            QuotesFilterOverflowAffordance(
                systemImage: systemImage,
                alignment: alignment
            )
            .allowsHitTesting(false)
        }
    }
}

enum QuotesBulkSelectionPresentationModel {
    static func reconciledSelection(
        _ selectedHighlightIDs: Set<UUID>,
        validHighlightIDs: [UUID]
    ) -> Set<UUID> {
        let validHighlightIDSet = Set(validHighlightIDs)
        return selectedHighlightIDs.intersection(validHighlightIDSet)
    }

    static func bulkDeleteHighlightIDs(
        from highlights: [Highlight],
        selectedHighlightIDs: Set<UUID>
    ) -> [UUID] {
        highlights.map(\.id).filter(selectedHighlightIDs.contains)
    }

    static func bulkDeleteButtonDisabled(
        isEditing: Bool,
        selectedHighlightIDs: Set<UUID>
    ) -> Bool {
        !isEditing || selectedHighlightIDs.isEmpty
    }

    static func reconciledPendingDeletionPlan(
        _ pendingPlan: BulkHighlightDeletionPlan?,
        validHighlightIDs: [UUID]
    ) -> BulkHighlightDeletionPlan? {
        guard let pendingPlan else {
            return nil
        }

        let reconciledPlan = pendingPlan.filtered(validHighlightIDs: Set(validHighlightIDs))
        return reconciledPlan.isEmpty ? nil : reconciledPlan
    }

    static func bulkDeleteConfirmationTitle(plan: BulkHighlightDeletionPlan) -> String {
        "Delete \(plan.highlightCount) \(plan.highlightCount == 1 ? "Quote" : "Quotes")?"
    }

    static func bulkDeleteConfirmationMessage(plan: BulkHighlightDeletionPlan) -> String {
        if plan.highlightCount == 1 {
            return "This quote will be permanently removed from your library."
        }

        return "This will permanently remove \(plan.highlightCount) selected quotes from your library."
    }

    static func resultCountSummary(
        displayedCount: Int,
        totalCount: Int,
        hasActiveQuery: Bool,
        isEditing: Bool,
        selectedCount: Int
    ) -> String {
        let displayedSummary = displayedSummaryText(
            displayedCount: displayedCount,
            totalCount: totalCount,
            hasActiveQuery: hasActiveQuery
        )

        guard isEditing || selectedCount > 0 else {
            return displayedSummary
        }

        return "\(displayedSummary) • \(selectedCount) selected"
    }

    private static func displayedSummaryText(
        displayedCount: Int,
        totalCount: Int,
        hasActiveQuery: Bool
    ) -> String {
        if totalCount == 0 {
            return "0 quotes"
        }

        let noun = displayedCount == 1 ? "quote" : "quotes"

        if !hasActiveQuery {
            return "\(displayedCount) \(noun)"
        }

        return "\(displayedCount) of \(totalCount) \(totalCount == 1 ? "quote" : "quotes")"
    }
}

enum QuotesHeaderPresentationModel {
    static func shouldShowImportHeader(
        isLoadingHighlights: Bool,
        totalHighlightCount: Int
    ) -> Bool {
        isLoadingHighlights || totalHighlightCount > 0
    }
}

#if TESTING
enum QuotesListViewTestProbe {
    struct SimulatedRefreshResult {
        let highlights: [Highlight]
        let totalMatchingHighlightCount: Int
        let availableBookTitles: [String]
        let availableAuthors: [String]
        let didAcceptPagePayload: Bool
        let didRequestFilterOptions: Bool
        let didAcceptFilterOptions: Bool
    }

    static func resolvedPrimaryContent(
        totalHighlightCount: Int,
        displayedRowCount: Int
    ) -> String {
        QuotesListContentPresentationModel.resolvedPrimaryContent(
            totalHighlightCount: totalHighlightCount,
            displayedRowCount: displayedRowCount
        ).rawValue
    }

    static func presentationState(
        isLoadingHighlights: Bool,
        lastResolvedPrimaryContent: String?,
        totalHighlightCount: Int,
        displayedRowCount: Int
    ) -> (primaryContent: String, showsRefreshOverlay: Bool) {
        let presentationState = QuotesListContentPresentationModel.presentationState(
            isLoadingHighlights: isLoadingHighlights,
            lastResolvedPrimaryContent: lastResolvedPrimaryContent.flatMap(QuotesListPrimaryContent.init(rawValue:)),
            totalHighlightCount: totalHighlightCount,
            displayedRowCount: displayedRowCount
        )

        return (
            primaryContent: presentationState.primaryContent.rawValue,
            showsRefreshOverlay: presentationState.showsRefreshOverlay
        )
    }

    static func reloadsFilterOptions(for reason: String) -> Bool {
        guard let refreshReason = QuotesListRefreshReason(rawValue: reason) else {
            return true
        }

        return QuotesListRefreshPresentationModel.reloadsFilterOptions(for: refreshReason)
    }

    static func shouldAcceptAsyncResult(
        capturedGeneration: Int,
        activeQueryGeneration: Int
    ) -> Bool {
        QuotesListRefreshPresentationModel.shouldAcceptAsyncResult(
            capturedGeneration: capturedGeneration,
            activeQueryGeneration: activeQueryGeneration
        )
    }

    static func committedSearchRefresh(
        rawSearchText: String,
        effectiveSearchText: String
    ) -> (effectiveSearchText: String, shouldRefresh: Bool) {
        let state = QuotesListSearchPresentationModel.commitSearchRefresh(
            rawSearchText: rawSearchText,
            effectiveSearchText: effectiveSearchText
        )
        return (
            effectiveSearchText: state.effectiveSearchText,
            shouldRefresh: state.shouldRefresh
        )
    }

    static func refreshQueryState(
        reason: String,
        effectiveSearchText: String,
        searchTextOverride: String? = nil
    ) -> (searchText: String, shouldCancelPendingSearchRefresh: Bool)? {
        guard let refreshReason = QuotesListRefreshReason(rawValue: reason) else {
            return nil
        }

        let state = QuotesListSearchPresentationModel.refreshQueryState(
            reason: refreshReason,
            effectiveSearchText: effectiveSearchText,
            searchTextOverride: searchTextOverride
        )
        return (
            searchText: state.searchText,
            shouldCancelPendingSearchRefresh: state.shouldCancelPendingSearchRefresh
        )
    }

    static func hasActiveQuery(
        effectiveSearchText: String,
        filters: QuotesListFilters
    ) -> Bool {
        QuotesListSearchPresentationModel.hasActiveQuery(
            effectiveSearchText: effectiveSearchText,
            filters: filters
        )
    }

    static func pagingSearchText(effectiveSearchText: String) -> String {
        QuotesListSearchPresentationModel.pagingSearchText(
            effectiveSearchText: effectiveSearchText
        )
    }

    static func simulateNativeSearchInput(
        typedValues: [String],
        onTextChanged: @escaping (String) -> Void
    ) -> [String] {
        let coordinator = QuotesLibrarySearchField.Coordinator(onTextChanged: onTextChanged)
        let searchField = NSSearchField(frame: .zero)
        var renderedValues: [String] = []

        for value in typedValues {
            searchField.stringValue = value
            coordinator.controlTextDidChange(
                Notification(
                    name: NSControl.textDidChangeNotification,
                    object: searchField
                )
            )
            renderedValues.append(searchField.stringValue)
        }

        return renderedValues
    }

    static func simulateRefresh(
        reason: String,
        capturedGeneration: Int,
        activeQueryGeneration: @escaping @Sendable () -> Int,
        preservingHighlights: [Highlight],
        totalMatchingHighlightCount: Int,
        availableBookTitles: [String],
        availableAuthors: [String],
        searchText: String,
        filters: QuotesListFilters,
        sortMode: QuotesListSortMode,
        quotesQueryService: QuotesQueryService
    ) async -> SimulatedRefreshResult {
        guard let refreshReason = QuotesListRefreshReason(rawValue: reason) else {
            return SimulatedRefreshResult(
                highlights: preservingHighlights,
                totalMatchingHighlightCount: totalMatchingHighlightCount,
                availableBookTitles: availableBookTitles,
                availableAuthors: availableAuthors,
                didAcceptPagePayload: false,
                didRequestFilterOptions: false,
                didAcceptFilterOptions: false
            )
        }

        var acceptedHighlights = preservingHighlights
        var acceptedTotalMatchingHighlightCount = totalMatchingHighlightCount
        var acceptedBookTitles = availableBookTitles
        var acceptedAuthors = availableAuthors

        let pagePayload = await quotesQueryService.loadPagePayload(
            searchText: searchText,
            filters: filters,
            sortedBy: sortMode,
            pageSize: QuotesListPagingConstants.pageSize
        )

        let didAcceptPagePayload = QuotesListRefreshPresentationModel.shouldAcceptAsyncResult(
            capturedGeneration: capturedGeneration,
            activeQueryGeneration: activeQueryGeneration()
        )
        guard didAcceptPagePayload else {
            return SimulatedRefreshResult(
                highlights: acceptedHighlights,
                totalMatchingHighlightCount: acceptedTotalMatchingHighlightCount,
                availableBookTitles: acceptedBookTitles,
                availableAuthors: acceptedAuthors,
                didAcceptPagePayload: false,
                didRequestFilterOptions: false,
                didAcceptFilterOptions: false
            )
        }

        acceptedHighlights = pagePayload.highlights
        acceptedTotalMatchingHighlightCount = pagePayload.totalMatchingHighlightCount

        let didRequestFilterOptions = QuotesListRefreshPresentationModel.reloadsFilterOptions(for: refreshReason)
        guard didRequestFilterOptions else {
            return SimulatedRefreshResult(
                highlights: acceptedHighlights,
                totalMatchingHighlightCount: acceptedTotalMatchingHighlightCount,
                availableBookTitles: acceptedBookTitles,
                availableAuthors: acceptedAuthors,
                didAcceptPagePayload: true,
                didRequestFilterOptions: false,
                didAcceptFilterOptions: false
            )
        }

        let filterOptions = await quotesQueryService.loadFilterOptions(
            searchText: searchText,
            filters: filters
        )

        let didAcceptFilterOptions = QuotesListRefreshPresentationModel.shouldAcceptAsyncResult(
            capturedGeneration: capturedGeneration,
            activeQueryGeneration: activeQueryGeneration()
        )
        guard didAcceptFilterOptions else {
            return SimulatedRefreshResult(
                highlights: acceptedHighlights,
                totalMatchingHighlightCount: acceptedTotalMatchingHighlightCount,
                availableBookTitles: acceptedBookTitles,
                availableAuthors: acceptedAuthors,
                didAcceptPagePayload: true,
                didRequestFilterOptions: true,
                didAcceptFilterOptions: false
            )
        }

        acceptedBookTitles = filterOptions.availableBookTitles
        acceptedAuthors = filterOptions.availableAuthors

        return SimulatedRefreshResult(
            highlights: acceptedHighlights,
            totalMatchingHighlightCount: acceptedTotalMatchingHighlightCount,
            availableBookTitles: acceptedBookTitles,
            availableAuthors: acceptedAuthors,
            didAcceptPagePayload: true,
            didRequestFilterOptions: true,
            didAcceptFilterOptions: true
        )
    }

    static func refreshResetState(after currentQueryGeneration: Int) -> (
        nextQueryGeneration: Int,
        isLoadingHighlights: Bool,
        isLoadingNextPage: Bool,
        hasMoreHighlights: Bool,
        highlightCount: Int,
        totalMatchingHighlightCount: Int,
        availableBookTitles: [String],
        availableAuthors: [String]
    ) {
        let state = QuotesListPagingPresentationModel.refreshResetState(
            queryGeneration: currentQueryGeneration + 1
        )
        return (
            nextQueryGeneration: state.queryGeneration,
            isLoadingHighlights: state.isLoadingHighlights,
            isLoadingNextPage: state.isLoadingNextPage,
            hasMoreHighlights: state.hasMoreHighlights,
            highlightCount: state.highlights.count,
            totalMatchingHighlightCount: state.totalMatchingHighlightCount,
            availableBookTitles: state.availableBookTitles,
            availableAuthors: state.availableAuthors
        )
    }

    static func refreshResetState(
        after currentQueryGeneration: Int,
        preservingHighlights: [Highlight],
        totalMatchingHighlightCount: Int,
        availableBookTitles: [String],
        availableAuthors: [String],
        selectedHighlightIDs: Set<UUID>
    ) -> (
        nextQueryGeneration: Int,
        isLoadingHighlights: Bool,
        isLoadingNextPage: Bool,
        hasMoreHighlights: Bool,
        highlightIDs: [UUID],
        totalMatchingHighlightCount: Int,
        availableBookTitles: [String],
        availableAuthors: [String],
        selectedHighlightIDs: Set<UUID>
    ) {
        let state = QuotesListPagingPresentationModel.refreshResetState(
            queryGeneration: currentQueryGeneration + 1,
            preservingHighlights: preservingHighlights,
            totalMatchingHighlightCount: totalMatchingHighlightCount,
            availableBookTitles: availableBookTitles,
            availableAuthors: availableAuthors,
            selectedHighlightIDs: selectedHighlightIDs
        )
        return (
            nextQueryGeneration: state.queryGeneration,
            isLoadingHighlights: state.isLoadingHighlights,
            isLoadingNextPage: state.isLoadingNextPage,
            hasMoreHighlights: state.hasMoreHighlights,
            highlightIDs: state.highlights.map(\.id),
            totalMatchingHighlightCount: state.totalMatchingHighlightCount,
            availableBookTitles: state.availableBookTitles,
            availableAuthors: state.availableAuthors,
            selectedHighlightIDs: state.selectedHighlightIDs
        )
    }

    static func hasMoreHighlights(
        loadedCount: Int,
        totalMatchingHighlightCount: Int
    ) -> Bool {
        QuotesListPagingPresentationModel.hasMoreHighlights(
            loadedCount: loadedCount,
            totalMatchingHighlightCount: totalMatchingHighlightCount
        )
    }

    static func shouldLoadMore(
        highlights: [Highlight],
        currentHighlightID: UUID,
        hasMoreHighlights: Bool,
        isLoadingHighlights: Bool,
        isLoadingNextPage: Bool,
        hasLoadMoreTask: Bool
    ) -> Bool {
        QuotesListPagingPresentationModel.shouldLoadMore(
            highlights: highlights,
            currentHighlightID: currentHighlightID,
            hasMoreHighlights: hasMoreHighlights,
            isLoadingHighlights: isLoadingHighlights,
            isLoadingNextPage: isLoadingNextPage,
            hasLoadMoreTask: hasLoadMoreTask
        )
    }

    static func appendPage(
        existingHighlights: [Highlight],
        nextPage: [Highlight],
        totalMatchingHighlightCount: Int
    ) -> (highlightIDs: [UUID], hasMoreHighlights: Bool) {
        let result = QuotesListPagingPresentationModel.appendPage(
            existingHighlights: existingHighlights,
            nextPage: nextPage,
            totalMatchingHighlightCount: totalMatchingHighlightCount
        )
        return (
            highlightIDs: result.highlights.map(\.id),
            hasMoreHighlights: result.hasMoreHighlights
        )
    }

    static func displayedHighlightIDs(
        from highlights: [Highlight],
        searchText: String,
        sortMode: QuotesListSortMode,
        books: [Book] = [],
        selectedBookTitle: String? = nil,
        selectedAuthor: String? = nil,
        bookStatus: QuotesListBookStatusFilterMode = .allBooks,
        source: QuotesListSourceFilterMode = .allQuotes
    ) -> [UUID] {
        let sortedHighlights = QuotesListPresentationModel.sortedHighlights(
            highlights,
            sortMode: sortMode
        )

        return QuotesListPresentationModel.displayedHighlights(
            from: sortedHighlights,
            searchText: searchText,
            filters: QuotesListFilters(
                selectedBookTitle: selectedBookTitle,
                selectedAuthor: selectedAuthor,
                bookStatus: bookStatus,
                source: source
            ),
            bookEnabledByID: Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0.isEnabled) })
        ).map(\.id)
    }

    static func filteredHighlightIDs(
        from highlights: [Highlight],
        searchText: String,
        books: [Book] = [],
        selectedBookTitle: String? = nil,
        selectedAuthor: String? = nil,
        bookStatus: QuotesListBookStatusFilterMode = .allBooks,
        source: QuotesListSourceFilterMode = .allQuotes
    ) -> [UUID] {
        QuotesListPresentationModel.displayedHighlights(
            from: highlights,
            searchText: searchText,
            filters: QuotesListFilters(
                selectedBookTitle: selectedBookTitle,
                selectedAuthor: selectedAuthor,
                bookStatus: bookStatus,
                source: source
            ),
            bookEnabledByID: Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0.isEnabled) })
        ).map(\.id)
    }

    static func previewText(for quoteText: String) -> String {
        QuotesListPresentationModel.previewText(for: quoteText)
    }

    static func rowModelsAreEquivalentForVisibleContent(
        first: Highlight,
        second: Highlight
    ) -> Bool {
        QuotesListRowModel(highlight: first) == QuotesListRowModel(highlight: second)
    }

    @MainActor
    static func retainedRowLastShownAtAfterEquivalentReplacement(
        initialHighlight: Highlight,
        replacementHighlight: Highlight
    ) -> Date? {
        let runtimeState = QuotesListRuntimeState()
        runtimeState.replaceRows(with: [initialHighlight])
        runtimeState.replaceRows(with: [replacementHighlight])
        return runtimeState.rowModels.first?.highlight.lastShownAt
    }

    @MainActor
    static func rowCountAfterRefreshStart(
        reason: String,
        preservingHighlights: [Highlight]
    ) -> Int? {
        guard let refreshReason = QuotesListRefreshReason(rawValue: reason) else {
            return nil
        }

        let runtimeState = QuotesListRuntimeState()
        runtimeState.replaceRows(with: preservingHighlights)
        runtimeState.queryGeneration += 1

        if refreshReason == .searchChanged {
            runtimeState.clearRows()
        }

        return runtimeState.rowModels.count
    }

    @MainActor
    static func rowIDsAfterSearchClearAndPotentiallyStaleResult(
        preservingHighlights: [Highlight],
        resultHighlights: [Highlight],
        capturedGeneration: Int,
        activeGeneration: Int
    ) -> [UUID] {
        let runtimeState = QuotesListRuntimeState()
        runtimeState.replaceRows(with: preservingHighlights)
        runtimeState.queryGeneration = activeGeneration
        runtimeState.clearRows()

        if QuotesListRefreshPresentationModel.shouldAcceptAsyncResult(
            capturedGeneration: capturedGeneration,
            activeQueryGeneration: runtimeState.queryGeneration
        ) {
            runtimeState.replaceRows(with: resultHighlights)
        }

        return runtimeState.rowModels.map(\.id)
    }

    static func bookTitleText(for highlight: Highlight) -> String {
        QuotesListPresentationModel.bookTitleText(for: highlight)
    }

    static func authorText(for highlight: Highlight) -> String {
        QuotesListPresentationModel.authorText(for: highlight)
    }

    static func availableBookTitles(from highlights: [Highlight]) -> [String] {
        QuotesListPresentationModel.availableBookTitles(from: highlights)
    }

    static func availableAuthors(from highlights: [Highlight]) -> [String] {
        QuotesListPresentationModel.availableAuthors(from: highlights)
    }

    static func reconciledSelection(
        _ selectedHighlightIDs: Set<UUID>,
        validHighlightIDs: [UUID]
    ) -> Set<UUID> {
        QuotesBulkSelectionPresentationModel.reconciledSelection(
            selectedHighlightIDs,
            validHighlightIDs: validHighlightIDs
        )
    }

    static func bulkDeleteHighlightIDs(
        from highlights: [Highlight],
        selectedHighlightIDs: Set<UUID>
    ) -> [UUID] {
        QuotesBulkSelectionPresentationModel.bulkDeleteHighlightIDs(
            from: highlights,
            selectedHighlightIDs: selectedHighlightIDs
        )
    }

    static func bulkDeleteButtonDisabled(
        isEditing: Bool,
        selectedHighlightIDs: Set<UUID>
    ) -> Bool {
        QuotesBulkSelectionPresentationModel.bulkDeleteButtonDisabled(
            isEditing: isEditing,
            selectedHighlightIDs: selectedHighlightIDs
        )
    }

    static func bulkDeleteConfirmationTitle(plan: BulkHighlightDeletionPlan) -> String {
        QuotesBulkSelectionPresentationModel.bulkDeleteConfirmationTitle(plan: plan)
    }

    static func bulkDeleteConfirmationTitle(selectedCount: Int) -> String {
        "Delete \(selectedCount) \(selectedCount == 1 ? "Quote" : "Quotes")?"
    }

    static func bulkDeleteConfirmationMessage(plan: BulkHighlightDeletionPlan) -> String {
        QuotesBulkSelectionPresentationModel.bulkDeleteConfirmationMessage(plan: plan)
    }

    static func bulkDeleteConfirmationMessage(selectedCount: Int) -> String {
        "This will permanently remove \(selectedCount) selected \(selectedCount == 1 ? "quote" : "quotes") from your library."
    }

    static func reconciledPendingDeletionPlan(
        _ pendingPlan: BulkHighlightDeletionPlan?,
        validHighlightIDs: [UUID]
    ) -> BulkHighlightDeletionPlan? {
        QuotesBulkSelectionPresentationModel.reconciledPendingDeletionPlan(
            pendingPlan,
            validHighlightIDs: validHighlightIDs
        )
    }

    static func resultCountSummary(
        displayedCount: Int,
        totalCount: Int,
        hasActiveQuery: Bool,
        isEditing: Bool,
        selectedCount: Int
    ) -> String {
        QuotesBulkSelectionPresentationModel.resultCountSummary(
            displayedCount: displayedCount,
            totalCount: totalCount,
            hasActiveQuery: hasActiveQuery,
            isEditing: isEditing,
            selectedCount: selectedCount
        )
    }

    static func shouldShowImportHeader(
        isLoadingHighlights: Bool,
        totalHighlightCount: Int
    ) -> Bool {
        QuotesHeaderPresentationModel.shouldShowImportHeader(
            isLoadingHighlights: isLoadingHighlights,
            totalHighlightCount: totalHighlightCount
        )
    }

    static func filterOverflowPresentationState(
        viewportWidth: CGFloat,
        contentWidth: CGFloat,
        contentOffset: CGFloat
    ) -> (showsLeadingAffordance: Bool, showsTrailingAffordance: Bool) {
        let state = QuotesFilterOverflowPresentationModel.presentationState(
            viewportWidth: viewportWidth,
            contentWidth: contentWidth,
            contentOffset: contentOffset
        )
        return (
            showsLeadingAffordance: state.showsLeadingAffordance,
            showsTrailingAffordance: state.showsTrailingAffordance
        )
    }
}

#endif
