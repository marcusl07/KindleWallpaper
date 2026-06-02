import SwiftUI

struct BooksListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedBookIDs: Set<UUID> = []
    @State private var pendingBulkBookDeletionPlan: BulkBookDeletionPlan? = nil
    @State private var isEditingBooks = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Books")
                .font(.title2.bold())

            HStack(spacing: 12) {
                Button("Enable All") {
                    appState.setAllBooksEnabled(true)
                }
                .disabled(
                    appState.isBookMutationInFlight ||
                    appState.books.isEmpty ||
                    appState.books.allSatisfy(\.isEnabled)
                )

                Button("Disable All") {
                    appState.setAllBooksEnabled(false)
                }
                .disabled(
                    appState.isBookMutationInFlight ||
                    appState.books.isEmpty ||
                    appState.books.allSatisfy { !$0.isEnabled }
                )

                Spacer(minLength: 12)
            }

            List(selection: $selectedBookIDs) {
                if appState.books.isEmpty {
                    Text("No books imported yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appState.books) { book in
                        bookToggleRow(book)
                            .tag(book.id)
                    }
                }
            }
            .listStyle(.inset)
            .onDeleteCommand {
                deleteSelectedBooks()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if allBooksDeselectedWarningVisible {
                Text("All books are deselected. Wallpaper rotation has no active quote pool.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive, action: deleteSelectedBooks) {
                    Label("Delete Selected", systemImage: "trash")
                }
                .disabled(selectedBookIDs.isEmpty)
                .help("Delete Selected Books")
            }
        }
        .onReceive(appState.$books) { _ in
            reconcileSelectedBooks()
        }
        .alert(
            BooksBulkSelectionPresentationModel.bulkDeleteConfirmationTitle(
                plan: pendingBulkBookDeletionPlanValue
            ),
            isPresented: bulkDeleteConfirmationPresentedBinding
        ) {
            Button("Delete", role: .destructive) {
                confirmBulkDeleteBooks()
            }
            Button("Cancel", role: .cancel) {
                pendingBulkBookDeletionPlan = nil
            }
        } message: {
            Text(
                BooksBulkSelectionPresentationModel.bulkDeleteConfirmationMessage(
                    plan: pendingBulkBookDeletionPlanValue
                )
            )
        }
    }

    private var allBooksDeselectedWarningVisible: Bool {
        !appState.books.isEmpty && appState.books.allSatisfy { !$0.isEnabled }
    }

    private var pendingBulkBookDeletionPlanValue: BulkBookDeletionPlan {
        pendingBulkBookDeletionPlan ?? BulkBookDeletionPlan(bookIDs: [], linkedHighlights: [])
    }

    private var bulkDeleteConfirmationPresentedBinding: Binding<Bool> {
        Binding(
            get: { pendingBulkBookDeletionPlan != nil },
            set: { isPresented in
                if !isPresented {
                    pendingBulkBookDeletionPlan = nil
                }
            }
        )
    }

    private func bookToggleRow(_ book: Book) -> some View {
        HStack(alignment: .center) {
            bookRowContent(book)
            Toggle("", isOn: bindingForBook(book))
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(appState.isBookMutationInFlight)
        }
        .contextMenu {
            Button("Delete Book...", role: .destructive) {
                let plan = appState.prepareBulkBookDeletion(bookIDs: [book.id])
                if !plan.isEmpty {
                    pendingBulkBookDeletionPlan = plan
                }
            }
        }
    }

    private func bookRowContent(_ book: Book) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(book.title)
                .font(.body.weight(.medium))
            Text(book.author)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text("\(book.highlightCount) \(book.highlightCount == 1 ? "highlight" : "highlights")")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reconcileSelectedBooks() {
        let reconciledSelection = BooksBulkSelectionPresentationModel.reconciledSelection(
            selectedBookIDs,
            validBookIDs: appState.books.map(\.id)
        )
        selectedBookIDs = reconciledSelection
        pendingBulkBookDeletionPlan = BooksBulkSelectionPresentationModel.reconciledPendingDeletionPlan(
            pendingBulkBookDeletionPlan,
            validBookIDs: appState.books.map(\.id)
        )
    }

    private func deleteSelectedBooks() {
        let bookIDsToDelete = BooksBulkSelectionPresentationModel.bulkDeleteBookIDs(
            from: appState.books,
            selectedBookIDs: selectedBookIDs
        )
        guard !bookIDsToDelete.isEmpty else {
            return
        }

        let plan = appState.prepareBulkBookDeletion(bookIDs: bookIDsToDelete)
        guard !plan.isEmpty else {
            pendingBulkBookDeletionPlan = nil
            return
        }

        pendingBulkBookDeletionPlan = plan
    }

    private func confirmBulkDeleteBooks() {
        guard let plan = pendingBulkBookDeletionPlan else {
            return
        }

        appState.deleteBooks(using: plan)
        pendingBulkBookDeletionPlan = nil
        selectedBookIDs.removeAll()
    }

    private func bindingForBook(_ book: Book) -> Binding<Bool> {
        Binding(
            get: {
                appState.books.first(where: { $0.id == book.id })?.isEnabled ?? false
            },
            set: { enabled in
                let currentEnabled = appState.books.first(where: { $0.id == book.id })?.isEnabled ?? false
                guard currentEnabled != enabled else {
                    return
                }
                appState.setBookEnabled(id: book.id, enabled: enabled)
            }
        )
    }
}

private enum BooksBulkSelectionPresentationModel {
    static func reconciledSelection(
        _ selectedBookIDs: Set<UUID>,
        validBookIDs: [UUID]
    ) -> Set<UUID> {
        let validBookIDSet = Set(validBookIDs)
        return selectedBookIDs.intersection(validBookIDSet)
    }

    static func bulkDeleteBookIDs(
        from books: [Book],
        selectedBookIDs: Set<UUID>
    ) -> [UUID] {
        books.map(\.id).filter(selectedBookIDs.contains)
    }

    static func bulkDeleteButtonDisabled(
        isEditing: Bool,
        selectedBookIDs: Set<UUID>
    ) -> Bool {
        selectedBookIDs.isEmpty
    }

    static func reconciledPendingDeletionPlan(
        _ pendingPlan: BulkBookDeletionPlan?,
        validBookIDs: [UUID]
    ) -> BulkBookDeletionPlan? {
        guard let pendingPlan else {
            return nil
        }

        let reconciledPlan = pendingPlan.filtered(validBookIDs: Set(validBookIDs))
        return reconciledPlan.isEmpty ? nil : reconciledPlan
    }

    static func bulkDeleteConfirmationTitle(plan: BulkBookDeletionPlan) -> String {
        "Delete \(plan.bookCount) \(plan.bookCount == 1 ? "Book" : "Books")?"
    }

    static func bulkDeleteConfirmationMessage(plan: BulkBookDeletionPlan) -> String {
        let bookText = "\(plan.bookCount) selected \(plan.bookCount == 1 ? "book" : "books")"
        let quoteText = "\(plan.linkedHighlightCount) linked \(plan.linkedHighlightCount == 1 ? "quote" : "quotes")"
        return "This will permanently remove \(bookText) and delete \(quoteText) from your library."
    }
}

#if TESTING
enum BooksListViewTestProbe {
    static func reconciledSelection(
        _ selectedBookIDs: Set<UUID>,
        validBookIDs: [UUID]
    ) -> Set<UUID> {
        BooksBulkSelectionPresentationModel.reconciledSelection(
            selectedBookIDs,
            validBookIDs: validBookIDs
        )
    }

    static func bulkDeleteBookIDs(
        from books: [Book],
        selectedBookIDs: Set<UUID>
    ) -> [UUID] {
        BooksBulkSelectionPresentationModel.bulkDeleteBookIDs(
            from: books,
            selectedBookIDs: selectedBookIDs
        )
    }

    static func bulkDeleteButtonDisabled(
        isEditing: Bool,
        selectedBookIDs: Set<UUID>
    ) -> Bool {
        BooksBulkSelectionPresentationModel.bulkDeleteButtonDisabled(
            isEditing: isEditing,
            selectedBookIDs: selectedBookIDs
        )
    }

    static func bulkDeleteConfirmationTitle(plan: BulkBookDeletionPlan) -> String {
        BooksBulkSelectionPresentationModel.bulkDeleteConfirmationTitle(plan: plan)
    }

    static func bulkDeleteConfirmationMessage(plan: BulkBookDeletionPlan) -> String {
        BooksBulkSelectionPresentationModel.bulkDeleteConfirmationMessage(plan: plan)
    }

    static func reconciledPendingDeletionPlan(
        _ pendingPlan: BulkBookDeletionPlan?,
        validBookIDs: [UUID]
    ) -> BulkBookDeletionPlan? {
        BooksBulkSelectionPresentationModel.reconciledPendingDeletionPlan(
            pendingPlan,
            validBookIDs: validBookIDs
        )
    }
}

#endif
