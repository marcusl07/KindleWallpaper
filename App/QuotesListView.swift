import SwiftUI

struct QuotesListView: View {
    private static let searchRefreshDebounceInterval: TimeInterval = 0.3
    private static let filterScrollCoordinateSpaceName = "QuotesFilterControlsScrollView"

    @EnvironmentObject private var appState: AppState
    @State private var effectiveSearchText = ""
    @State private var sortMode: QuotesListSortMode = .mostRecentlyAdded
    @State private var filters = QuotesListFilters()
    @State private var selectedHighlightIDs: Set<UUID> = []
    @State private var pendingBulkDeletePlan: BulkHighlightDeletionPlan? = nil
    @State private var isEditingHighlights = false
    @State private var isPresentingAddQuote = false
    @State private var filterControlsViewportWidth: CGFloat = 0
    @State private var filterControlsContentWidth: CGFloat = 0
    @State private var filterControlsContentOffset: CGFloat = 0
    @StateObject private var runtimeState = QuotesListRuntimeState()

    private let searchRefreshDebounceInterval: TimeInterval
    private let searchRefreshDebounceScheduler: DebouncedTaskScheduler
    private let onNavigateToQuote: (UUID) -> Void

    init(
        searchRefreshDebounceInterval: TimeInterval = QuotesListView.searchRefreshDebounceInterval,
        searchRefreshDebounceScheduler: DebouncedTaskScheduler = DebouncedTaskScheduler(),
        onNavigateToQuote: @escaping (UUID) -> Void = { _ in }
    ) {
        self.searchRefreshDebounceInterval = searchRefreshDebounceInterval
        self.searchRefreshDebounceScheduler = searchRefreshDebounceScheduler
        self.onNavigateToQuote = onNavigateToQuote
    }

    var body: some View {
        let displayedRows = runtimeState.rowModels
        let contentPresentation = QuotesListContentPresentationModel.presentationState(
            isLoadingHighlights: runtimeState.isLoadingHighlights,
            lastResolvedPrimaryContent: runtimeState.lastResolvedPrimaryContent,
            totalHighlightCount: appState.totalHighlightCount,
            displayedRowCount: displayedRows.count
        )

        return VStack(alignment: .leading, spacing: 16) {
            Text("Quotes")
                .font(.title2.bold())

            if shouldShowImportHeader {
                QuotesImportHeaderView()
            }

            QuotesListControlsRow(
                committedSearchText: effectiveSearchText,
                sortMode: $sortMode,
                filters: $filters,
                resultCountSummary: resultCountSummary(displayedCount: displayedRows.count),
                filterControlsViewportWidth: $filterControlsViewportWidth,
                filterControlsContentWidth: $filterControlsContentWidth,
                filterControlsContentOffset: $filterControlsContentOffset,
                onSearchTextChanged: scheduleSearchRefresh(rawSearchText:)
                // onTextChanged: scheduleSearchRefresh(rawSearchText:)
            )

            Group {
                if contentPresentation.primaryContent == .initialLoading {
                    ProgressView("Loading Quotes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if contentPresentation.primaryContent == .libraryEmpty {
                    QuotesLibraryEmptyStateView()
                } else if contentPresentation.primaryContent == .noMatchingResults {
                    QuotesEmptyStateView(
                        title: "No Matching Quotes",
                        systemImage: "magnifyingglass",
                        description: "Try a different search term or adjust the filters."
                    )
                } else {
                    quotesList(displayedRows: displayedRows)
                }
            }
            .overlay {
                if contentPresentation.showsRefreshOverlay {
                    refreshOverlay
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .background(
            QuotesListRenderCompletionObserver(
                token: runtimeState.renderObservationToken,
                displayedCount: displayedRows.count,
                onRendered: completeRenderMeasurement
            )
            .frame(width: 0, height: 0)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive, action: deleteSelectedHighlights) {
                    Label("Delete Selected", systemImage: "trash")
                }
                .disabled(selectedHighlightIDs.isEmpty)
                .help("Delete Selected Quotes")

                Button {
                    isPresentingAddQuote = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Quote")
            }
        }
        .sheet(isPresented: $isPresentingAddQuote) {
            QuoteEditView(
                highlight: nil,
                books: appState.books,
                onCancel: {
                    isPresentingAddQuote = false
                },
                onSave: { request in
                    appState.addManualQuote(request)
                    isPresentingAddQuote = false
                }
            )
            .frame(minWidth: 520, minHeight: 460)
        }
        .onAppear {
            refreshHighlights(reason: .appear)
        }
        .onChange(of: sortMode) { _ in
            refreshHighlights(reason: .sortChanged)
        }
        .onChange(of: filters.selectedBookTitle) { _ in
            refreshHighlights(reason: .bookFilterChanged)
        }
        .onChange(of: filters.selectedAuthor) { _ in
            refreshHighlights(reason: .authorFilterChanged)
        }
        .onChange(of: filters.bookStatus) { _ in
            refreshHighlights(reason: .bookStatusChanged)
        }
        .onChange(of: filters.source) { _ in
            refreshHighlights(reason: .sourceFilterChanged)
        }
        .onReceive(appState.$totalHighlightCount) { _ in
            refreshHighlights(reason: .libraryChanged)
        }
        .onDisappear(perform: cancelQuotesLoading)
        .alert(
            QuotesBulkSelectionPresentationModel.bulkDeleteConfirmationTitle(
                plan: pendingBulkDeletePlanValue
            ),
            isPresented: bulkDeleteConfirmationPresentedBinding
        ) {
            Button("Delete", role: .destructive) {
                confirmBulkDeleteHighlights()
            }
            Button("Cancel", role: .cancel) {
                pendingBulkDeletePlan = nil
            }
        } message: {
            Text(
                QuotesBulkSelectionPresentationModel.bulkDeleteConfirmationMessage(
                    plan: pendingBulkDeletePlanValue
                )
            )
        }
    }

    private func quotesList(displayedRows: [QuotesListRowModel]) -> some View {
        // List(selection: $selectedHighlightIDs)
        QuotesNativeTableView(
            rows: displayedRows,
            selectedHighlightIDs: $selectedHighlightIDs,
            isLoadingNextPage: runtimeState.isLoadingNextPage,
            onLoadMore: loadMoreIfNeeded(currentHighlightID:),
            onNavigateToQuote: onNavigateToQuote,
            onSetWallpaper: { quoteID in
                if let highlight = appState.loadHighlight(id: quoteID) {
                    _ = appState.requestWallpaperRotation(forcedHighlight: highlight)
                }
            },
            onDeleteQuotes: { ids in
                let plan = appState.prepareBulkHighlightDeletion(highlightIDs: ids)
                if !plan.isEmpty {
                    pendingBulkDeletePlan = plan
                }
            }
        )
    }

    private var refreshOverlay: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .opacity(0.7)

            ProgressView("Loading Quotes…")
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
        .transition(.opacity)
    }

    private func resultCountSummary(displayedCount: Int) -> String {
        QuotesBulkSelectionPresentationModel.resultCountSummary(
            displayedCount: displayedCount,
            totalCount: runtimeState.totalMatchingHighlightCount,
            hasActiveQuery: hasActiveQuery,
            isEditing: isEditingHighlights,
            selectedCount: selectedHighlightIDs.count
        )
    }

    private var shouldShowImportHeader: Bool {
        QuotesHeaderPresentationModel.shouldShowImportHeader(
            isLoadingHighlights: runtimeState.isLoadingHighlights,
            totalHighlightCount: appState.totalHighlightCount
        )
    }

    private var hasActiveQuery: Bool {
        QuotesListSearchPresentationModel.hasActiveQuery(
            effectiveSearchText: effectiveSearchText,
            filters: filters
        )
    }

    private var deleteSelectedHelpText: String {
        if !isEditingHighlights {
            return "Enter Edit Mode to Delete Quotes"
        }

        if selectedHighlightIDs.isEmpty {
            return "Select Quotes to Delete"
        }

        return "Delete Selected Quotes"
    }

    private var bulkDeleteConfirmationPresentedBinding: Binding<Bool> {
        Binding(
            get: { pendingBulkDeletePlan != nil },
            set: { isPresented in
                if !isPresented {
                    pendingBulkDeletePlan = nil
                }
            }
        )
    }

    private var pendingBulkDeletePlanValue: BulkHighlightDeletionPlan {
        pendingBulkDeletePlan ?? BulkHighlightDeletionPlan(highlights: [])
    }

    private func refreshHighlights() {
        refreshHighlights(reason: .refresh)
    }

    private func refreshHighlights(
        reason: QuotesListRefreshReason,
        searchTextOverride: String? = nil
    ) {
        let refreshQueryState = QuotesListSearchPresentationModel.refreshQueryState(
            reason: reason,
            effectiveSearchText: effectiveSearchText,
            searchTextOverride: searchTextOverride
        )

        if refreshQueryState.shouldCancelPendingSearchRefresh {
            cancelPendingSearchRefresh()
        }

        cancelActiveQuotesTasks()
        cancelPendingMeasurements()

        let currentGeneration = runtimeState.queryGeneration + 1
        // let currentGeneration = queryGeneration + 1
        runtimeState.queryGeneration = currentGeneration
        if reason == .searchChanged {
            runtimeState.clearRows()
        }

        let resetState = QuotesListPagingPresentationModel.refreshResetState(
            queryGeneration: currentGeneration,
            preservingHighlights: runtimeState.highlights,
            totalMatchingHighlightCount: runtimeState.totalMatchingHighlightCount,
            availableBookTitles: runtimeState.availableBookTitles,
            availableAuthors: runtimeState.availableAuthors,
            selectedHighlightIDs: selectedHighlightIDs
        )
        runtimeState.isLoadingHighlights = resetState.isLoadingHighlights
        runtimeState.isLoadingNextPage = resetState.isLoadingNextPage
        runtimeState.hasMoreHighlights = resetState.hasMoreHighlights
        runtimeState.highlights = resetState.highlights
        runtimeState.totalMatchingHighlightCount = resetState.totalMatchingHighlightCount
        runtimeState.availableBookTitles = resetState.availableBookTitles
        runtimeState.availableAuthors = resetState.availableAuthors
        selectedHighlightIDs = resetState.selectedHighlightIDs

        runtimeState.pendingRefreshSignpostState = QuotesListPerformanceSignposts.beginRefresh(
            reason: reason.rawValue,
            sortMode: sortMode
        )

        let currentSearchText = refreshQueryState.searchText
        let currentFilters = filters
        let currentSortMode = sortMode
        let quotesQueryService = appState.quotesQueryService
        let reloadsFilterOptions = QuotesListRefreshPresentationModel.reloadsFilterOptions(for: reason)
        runtimeState.refreshTask = Task {
            let snapshot: QuotesQuerySnapshot
            if reloadsFilterOptions {
                snapshot = await quotesQueryService.loadSnapshot(
                    searchText: currentSearchText,
                    filters: currentFilters,
                    sortedBy: currentSortMode,
                    pageSize: QuotesListPagingConstants.pageSize
                )
            } else {
                let pagePayload = await quotesQueryService.loadPagePayload(
                    searchText: currentSearchText,
                    filters: currentFilters,
                    sortedBy: currentSortMode,
                    pageSize: QuotesListPagingConstants.pageSize
                )
                snapshot = QuotesQuerySnapshot(
                    highlights: pagePayload.highlights,
                    totalMatchingHighlightCount: pagePayload.totalMatchingHighlightCount,
                    availableBookTitles: [],
                    availableAuthors: []
                )
            }

            guard !Task.isCancelled,
                  QuotesListRefreshPresentationModel.shouldAcceptAsyncResult(
                    capturedGeneration: currentGeneration,
                    activeQueryGeneration: runtimeState.queryGeneration
                  ) else {
                return
            }

            runtimeState.highlights = snapshot.highlights
            runtimeState.totalMatchingHighlightCount = snapshot.totalMatchingHighlightCount
            runtimeState.hasMoreHighlights = QuotesListPagingPresentationModel.hasMoreHighlights(
                loadedCount: snapshot.highlights.count,
                totalMatchingHighlightCount: snapshot.totalMatchingHighlightCount
            )
            runtimeState.isLoadingHighlights = false
            runtimeState.lastResolvedPrimaryContent = QuotesListContentPresentationModel.resolvedPrimaryContent(
                totalHighlightCount: appState.totalHighlightCount,
                displayedRowCount: snapshot.highlights.count
            )
            runtimeState.replaceRows(with: snapshot.highlights)
            reconcileSelectedHighlights()
            completeRefreshMeasurement(loadedCount: snapshot.highlights.count)

            runtimeState.pendingRenderSignpostState = QuotesListPerformanceSignposts.beginRender(
                reason: reason.rawValue,
                sortMode: currentSortMode,
                totalCount: snapshot.highlights.count
            )
            runtimeState.renderObservationToken = UUID()

            guard reloadsFilterOptions else {
                runtimeState.refreshTask = nil
                return
            }

            runtimeState.availableBookTitles = snapshot.availableBookTitles
            runtimeState.availableAuthors = snapshot.availableAuthors

            guard reconcileFilters() == false else {
                runtimeState.refreshTask = nil
                return
            }

            runtimeState.refreshTask = nil
        }
    }

    private func completeRenderMeasurement(token: UUID, displayedCount: Int) {
        guard token == runtimeState.renderObservationToken,
              let pendingRenderSignpostState = runtimeState.pendingRenderSignpostState else {
            return
        }

        QuotesListPerformanceSignposts.endRender(
            pendingRenderSignpostState,
            displayedCount: displayedCount
        )
        runtimeState.pendingRenderSignpostState = nil
    }

    private func cancelPendingMeasurements() {
        cancelPendingRefreshMeasurement()
        cancelPendingRenderMeasurement()
    }

    private func cancelPendingRefreshMeasurement() {
        guard let pendingRefreshSignpostState = runtimeState.pendingRefreshSignpostState else {
            return
        }

        QuotesListPerformanceSignposts.cancelRefresh(pendingRefreshSignpostState)
        runtimeState.pendingRefreshSignpostState = nil
    }

    private func cancelPendingRenderMeasurement() {
        guard let pendingRenderSignpostState = runtimeState.pendingRenderSignpostState else {
            return
        }

        QuotesListPerformanceSignposts.cancelRender(pendingRenderSignpostState)
        runtimeState.pendingRenderSignpostState = nil
    }

    private func completeRefreshMeasurement(loadedCount: Int) {
        guard let pendingRefreshSignpostState = runtimeState.pendingRefreshSignpostState else {
            return
        }

        QuotesListPerformanceSignposts.endRefresh(
            pendingRefreshSignpostState,
            loadedCount: loadedCount
        )
        runtimeState.pendingRefreshSignpostState = nil
    }

    private func reconcileFilters() -> Bool {
        var didChange = false

        if let selectedBookTitle = filters.selectedBookTitle,
           !runtimeState.availableBookTitles.contains(selectedBookTitle) {
            filters.selectedBookTitle = nil
            didChange = true
        }

        if let selectedAuthor = filters.selectedAuthor,
           !runtimeState.availableAuthors.contains(selectedAuthor) {
            filters.selectedAuthor = nil
            didChange = true
        }

        return didChange
    }

    private func reconcileSelectedHighlights() {
        let reconciledSelection = QuotesBulkSelectionPresentationModel.reconciledSelection(
            selectedHighlightIDs,
            validHighlightIDs: runtimeState.highlights.map(\.id)
        )
        selectedHighlightIDs = reconciledSelection
        pendingBulkDeletePlan = QuotesBulkSelectionPresentationModel.reconciledPendingDeletionPlan(
            pendingBulkDeletePlan,
            validHighlightIDs: runtimeState.highlights.map(\.id)
        )
    }

    private func toggleHighlightsEditMode() {
        isEditingHighlights.toggle()

        if !isEditingHighlights {
            selectedHighlightIDs.removeAll()
        }
    }

    private func loadMoreIfNeeded(currentHighlightID: UUID) {
        guard QuotesListPagingPresentationModel.shouldLoadMore(
            highlights: runtimeState.highlights,
            currentHighlightID: currentHighlightID,
            hasMoreHighlights: runtimeState.hasMoreHighlights,
            isLoadingHighlights: runtimeState.isLoadingHighlights,
            isLoadingNextPage: runtimeState.isLoadingNextPage,
            hasLoadMoreTask: runtimeState.loadMoreTask != nil
        ) else {
            return
        }

        runtimeState.isLoadingNextPage = true
        let currentGeneration = runtimeState.queryGeneration
        let currentSearchText = QuotesListSearchPresentationModel.pagingSearchText(
            effectiveSearchText: effectiveSearchText
        )
        let currentFilters = filters
        let currentSortMode = sortMode
        let currentOffset = runtimeState.highlights.count
        let quotesQueryService = appState.quotesQueryService

        runtimeState.loadMoreTask = Task {
            let nextPage = await quotesQueryService.loadPage(
                searchText: currentSearchText,
                filters: currentFilters,
                sortedBy: currentSortMode,
                limit: QuotesListPagingConstants.pageSize,
                offset: currentOffset
            )

            guard !Task.isCancelled, currentGeneration == runtimeState.queryGeneration else {
                return
            }

            let appendResult = QuotesListPagingPresentationModel.appendPage(
                existingHighlights: runtimeState.highlights,
                nextPage: nextPage,
                totalMatchingHighlightCount: runtimeState.totalMatchingHighlightCount
            )
            let existingHighlightIDs = Set(runtimeState.highlights.map(\.id))
            let uniqueNextPage = nextPage.filter { !existingHighlightIDs.contains($0.id) }
            runtimeState.highlights = appendResult.highlights
            runtimeState.appendRows(from: uniqueNextPage)
            runtimeState.hasMoreHighlights = appendResult.hasMoreHighlights
            runtimeState.isLoadingNextPage = false
            runtimeState.loadMoreTask = nil
            reconcileSelectedHighlights()
        }
    }

    private func cancelActiveQuotesTasks() {
        runtimeState.refreshTask?.cancel()
        runtimeState.refreshTask = nil
        runtimeState.loadMoreTask?.cancel()
        runtimeState.loadMoreTask = nil
        runtimeState.isLoadingHighlights = false
        runtimeState.isLoadingNextPage = false
    }

    private func cancelQuotesLoading() {
        cancelPendingSearchRefresh()
        cancelActiveQuotesTasks()
        cancelPendingMeasurements()
    }

    private func scheduleSearchRefresh(rawSearchText: String) {
        runtimeState.pendingSearchRefreshTask = searchRefreshDebounceScheduler.schedule(
            after: searchRefreshDebounceInterval,
            replacing: runtimeState.pendingSearchRefreshTask
        ) {
            runtimeState.pendingSearchRefreshTask = nil
            let commitState = QuotesListSearchPresentationModel.commitSearchRefresh(
                rawSearchText: rawSearchText,
                effectiveSearchText: effectiveSearchText
            )
            effectiveSearchText = commitState.effectiveSearchText

            guard commitState.shouldRefresh else {
                return
            }

            refreshHighlights(
                reason: .searchChanged,
                searchTextOverride: commitState.effectiveSearchText
            )
        }
    }

    private func cancelPendingSearchRefresh() {
        runtimeState.pendingSearchRefreshTask?.cancel()
        runtimeState.pendingSearchRefreshTask = nil
    }

    private func deleteSelectedHighlights() {
        let highlightIDsToDelete = QuotesBulkSelectionPresentationModel.bulkDeleteHighlightIDs(
            from: runtimeState.highlights,
            selectedHighlightIDs: selectedHighlightIDs
        )
        guard !highlightIDsToDelete.isEmpty else {
            return
        }

        let plan = appState.prepareBulkHighlightDeletion(highlightIDs: highlightIDsToDelete)
        guard !plan.isEmpty else {
            pendingBulkDeletePlan = nil
            return
        }

        pendingBulkDeletePlan = plan
    }

    private func confirmBulkDeleteHighlights() {
        guard let plan = pendingBulkDeletePlan else {
            return
        }

        // Legacy path was appState.deleteHighlights(ids: highlightIDsToDelete); confirmation now uses the captured plan.
        appState.deleteHighlights(using: plan)
        pendingBulkDeletePlan = nil
        selectedHighlightIDs.removeAll()
    }
}

struct QuotesEmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(.init(description))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct QuotesLibraryEmptyStateView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "quote.opening")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(.secondary)

            Text("No Quotes Yet")
                .font(.title3.bold())

            Text("Import `My Clippings.txt` or plug in your Kindle to build your quote library.")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)

            VStack(spacing: 12) {
                Button("Import My Clippings.txt...") {
                    chooseClippingsFile(for: appState)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if let importError = appState.importError, !importError.isEmpty {
                    Text(importError)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                } else if !appState.importStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(appState.importStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                if !appState.importWarningDetails.isEmpty {
                    DisclosureGroup("Warning details") {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(appState.importWarningDetails.enumerated()), id: \.offset) { _, detail in
                                Text(detail)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .padding(.top, 4)
                    }
                    .font(.callout)
                    .frame(maxWidth: 400)
                }
            }
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
