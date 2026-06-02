import SwiftUI

struct QuoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var highlight: Highlight
    @State private var pendingDeletePlan: BulkHighlightDeletionPlan? = nil
    @State private var isPresentingEditQuote = false
    @State private var wallpaperRequestMessage: String?
    @State private var toggleMessage: String?

    init(highlight: Highlight) {
        _highlight = State(initialValue: highlight)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Quote Detail")
                    .font(.title2.bold())

                VStack(alignment: .leading, spacing: 12) {
                    Text(highlight.quoteText)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(QuotesListPresentationModel.bookTitleText(for: highlight))
                            .font(.headline)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(QuotesListPresentationModel.authorText(for: highlight))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button("Edit") {
                        isPresentingEditQuote = true
                    }
                    .buttonStyle(.bordered)

                    Button("Set as Current Wallpaper") {
                        let didRequestRotation = appState.requestWallpaperRotation(forcedHighlight: highlight)
                        wallpaperRequestMessage = didRequestRotation
                            ? "Wallpaper update requested."
                            : "Wallpaper update already in progress."
                    }
                    .buttonStyle(.borderedProminent)

                    Button(Self.toggleButtonTitle(isEnabled: highlight.isEnabled)) {
                        toggleHighlightEnabled()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Delete Quote", role: .destructive) {
                    prepareDeleteConfirmation()
                }

                if let wallpaperRequestMessage {
                    Text(wallpaperRequestMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let toggleMessage {
                    Text(toggleMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    detailRow(label: "Location", value: detailLocationText)
                    detailRow(label: "Date Added", value: formattedDate(highlight.dateAdded))
                    detailRow(label: "Last Shown", value: formattedDate(highlight.lastShownAt))
                    detailRow(
                        label: "Included in Rotation",
                        value: Self.effectiveRotationStatusText(
                            quoteIsEnabled: highlight.isEnabled,
                            bookIsEnabled: linkedBookIsEnabled
                        )
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Quote")
        .sheet(isPresented: $isPresentingEditQuote) {
            QuoteEditView(
                highlight: highlight,
                books: appState.books,
                onCancel: {
                    isPresentingEditQuote = false
                },
                onSave: { request in
                    let updatedHighlight = try appState.updateQuote(highlight, with: request)
                    highlight = updatedHighlight
                    wallpaperRequestMessage = nil
                    toggleMessage = nil
                    isPresentingEditQuote = false
                }
            )
            .frame(minWidth: 520, minHeight: 460)
        }
        .onReceive(appState.$totalHighlightCount) { _ in
            reconcilePendingDeletePlan()
        }
        .alert("Delete Quote?", isPresented: deleteConfirmationPresentedBinding) {
            Button("Delete", role: .destructive) {
                confirmDelete()
                dismiss()
            }
            Button("Cancel", role: .cancel) {
                pendingDeletePlan = nil
            }
        } message: {
            Text(QuotesBulkSelectionPresentationModel.bulkDeleteConfirmationMessage(plan: pendingDeletePlanValue))
        }
    }

    private var pendingDeletePlanValue: BulkHighlightDeletionPlan {
        pendingDeletePlan ?? BulkHighlightDeletionPlan(highlights: [])
    }

    private var deleteConfirmationPresentedBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletePlan != nil },
            set: { isPresented in
                if !isPresented {
                    pendingDeletePlan = nil
                }
            }
        )
    }

    private var detailLocationText: String {
        let trimmedLocation = highlight.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedLocation.isEmpty ? "Not available" : trimmedLocation
    }

    private var linkedBookIsEnabled: Bool? {
        guard let bookID = highlight.bookId else {
            return nil
        }

        return appState.books.first(where: { $0.id == bookID })?.isEnabled
    }

    private func prepareDeleteConfirmation() {
        let plan = appState.prepareBulkHighlightDeletion(highlightIDs: [highlight.id])
        pendingDeletePlan = plan.isEmpty ? nil : plan
    }

    private func reconcilePendingDeletePlan() {
        guard let pendingDeletePlan else {
            return
        }

        let refreshedPlan = appState.prepareBulkHighlightDeletion(highlightIDs: pendingDeletePlan.highlightIDs)
        self.pendingDeletePlan = refreshedPlan.isEmpty ? nil : refreshedPlan
    }

    private func confirmDelete() {
        guard let pendingDeletePlan else {
            return
        }

        appState.deleteHighlights(using: pendingDeletePlan)
        self.pendingDeletePlan = nil
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "Not available"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func toggleHighlightEnabled() {
        let enabled = !highlight.isEnabled
        appState.setHighlightEnabled(id: highlight.id, enabled: enabled)

        let updatedHighlight = Self.updatedHighlight(highlight, isEnabled: enabled)
        highlight = updatedHighlight
        toggleMessage = Self.toggleStatusMessage(
            isEnabled: enabled,
            bookIsEnabled: linkedBookIsEnabled
        )
    }

    static func toggleButtonTitle(isEnabled: Bool) -> String {
        isEnabled ? "Disable from Rotation" : "Enable for Rotation"
    }

    static func effectiveRotationStatusText(quoteIsEnabled: Bool, bookIsEnabled: Bool?) -> String {
        guard quoteIsEnabled else {
            return "No"
        }

        if bookIsEnabled == false {
            return "No (book disabled)"
        }

        return "Yes"
    }

    static func toggleStatusMessage(isEnabled: Bool, bookIsEnabled: Bool?) -> String {
        if isEnabled {
            return bookIsEnabled == false
                ? "Quote enabled. It will rotate once its book is enabled."
                : "Quote enabled for rotation."
        }

        return "Quote removed from rotation."
    }

    static func updatedHighlight(_ highlight: Highlight, isEnabled: Bool) -> Highlight {
        Highlight(
            id: highlight.id,
            bookId: highlight.bookId,
            quoteText: highlight.quoteText,
            bookTitle: highlight.bookTitle,
            author: highlight.author,
            location: highlight.location,
            dateAdded: highlight.dateAdded,
            lastShownAt: isEnabled ? nil : highlight.lastShownAt,
            isEnabled: isEnabled
        )
    }
}


#if TESTING
enum QuoteDetailViewTestProbe {
    static func toggleButtonTitle(isEnabled: Bool) -> String {
        QuoteDetailView.toggleButtonTitle(isEnabled: isEnabled)
    }

    static func effectiveRotationStatusText(quoteIsEnabled: Bool, bookIsEnabled: Bool?) -> String {
        QuoteDetailView.effectiveRotationStatusText(quoteIsEnabled: quoteIsEnabled, bookIsEnabled: bookIsEnabled)
    }

    static func toggleStatusMessage(isEnabled: Bool, bookIsEnabled: Bool?) -> String {
        QuoteDetailView.toggleStatusMessage(isEnabled: isEnabled, bookIsEnabled: bookIsEnabled)
    }

    static func updatedHighlight(_ highlight: Highlight, isEnabled: Bool) -> Highlight {
        QuoteDetailView.updatedHighlight(highlight, isEnabled: isEnabled)
    }
}

#endif
