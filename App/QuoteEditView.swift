import SwiftUI

struct QuoteEditSaveRequest {
    let bookId: UUID?
    let quoteText: String
    let bookTitle: String
    let author: String
    let location: String?
}

private struct QuoteEditDraft {
    var quoteText: String
    var bookTitle: String
    var author: String
    var location: String

    init(
        quoteText: String,
        bookTitle: String,
        author: String,
        location: String
    ) {
        self.quoteText = quoteText
        self.bookTitle = bookTitle
        self.author = author
        self.location = location
    }

    init(highlight: Highlight?) {
        quoteText = highlight?.quoteText ?? ""
        bookTitle = highlight?.bookTitle ?? ""
        author = highlight?.author ?? ""
        location = highlight?.location ?? ""
    }
}

private enum QuoteEditPresentationModel {
    static func title(for highlight: Highlight?) -> String {
        highlight == nil ? "Add Quote" : "Edit Quote"
    }

    static func errorMessage(for error: AppState.QuoteSaveError) -> String {
        error.errorDescription ?? "Unable to save this quote."
    }

    static func errorRecoverySuggestion(for error: AppState.QuoteSaveError) -> String? {
        error.recoverySuggestion
    }

    static func canSave(quoteText: String) -> Bool {
        !trimmedValue(quoteText).isEmpty
    }

    static func matchedBook(
        bookTitle: String,
        author: String,
        books: [Book]
    ) -> Book? {
        guard
            let normalizedTitle = normalizedMatchValue(bookTitle),
            let normalizedAuthor = normalizedMatchValue(author)
        else {
            return nil
        }

        return books.first { book in
            normalizedMatchValue(book.title) == normalizedTitle &&
            normalizedMatchValue(book.author) == normalizedAuthor
        }
    }

    static func saveRequest(
        draft: QuoteEditDraft,
        books: [Book]
    ) -> QuoteEditSaveRequest {
        let trimmedQuoteText = trimmedValue(draft.quoteText)
        let trimmedLocation = trimmedOptionalValue(draft.location)

        if let matchedBook = matchedBook(
            bookTitle: draft.bookTitle,
            author: draft.author,
            books: books
        ) {
            return QuoteEditSaveRequest(
                bookId: matchedBook.id,
                quoteText: trimmedQuoteText,
                bookTitle: matchedBook.title,
                author: matchedBook.author,
                location: trimmedLocation
            )
        }

        return QuoteEditSaveRequest(
            bookId: nil,
            quoteText: trimmedQuoteText,
            bookTitle: trimmedValue(draft.bookTitle),
            author: trimmedValue(draft.author),
            location: trimmedLocation
        )
    }

    private static func normalizedMatchValue(_ rawValue: String) -> String? {
        let trimmed = trimmedValue(rawValue)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func trimmedValue(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedOptionalValue(_ rawValue: String) -> String? {
        let trimmed = trimmedValue(rawValue)
        return trimmed.isEmpty ? nil : trimmed
    }
}

struct QuoteEditView: View {
    let highlight: Highlight?
    let books: [Book]
    let onCancel: () -> Void
    let onSave: (QuoteEditSaveRequest) throws -> Void

    @State private var draft: QuoteEditDraft
    @State private var saveError: AppState.QuoteSaveError?

    init(
        highlight: Highlight?,
        books: [Book],
        onCancel: @escaping () -> Void,
        onSave: @escaping (QuoteEditSaveRequest) throws -> Void
    ) {
        self.highlight = highlight
        self.books = books
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: QuoteEditDraft(highlight: highlight))
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.title2.bold())
                .padding(.top, 24)
                .padding(.horizontal, 24)
                .frame(maxWidth: .infinity, alignment: .leading)

            Form {
                if let saveError {
                    Section {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Unable to Save Quote", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)

                            Text(QuoteEditPresentationModel.errorMessage(for: saveError))
                                .fixedSize(horizontal: false, vertical: true)

                            if let recoverySuggestion = QuoteEditPresentationModel.errorRecoverySuggestion(for: saveError) {
                                Text(recoverySuggestion)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Button("Dismiss") {
                                self.saveError = nil
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("Quote") {
                    TextEditor(text: $draft.quoteText)
                        .frame(minHeight: 180)
                }

                Section("Details") {
                    TextField("Book Title", text: $draft.bookTitle)
                    TextField("Author", text: $draft.author)
                    TextField("Location", text: $draft.location)

                    LabeledContent("Linked Book") {
                        if let matchedBook {
                            Text("\(matchedBook.title) by \(matchedBook.author)")
                        } else {
                            Text("None")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            HStack(spacing: 12) {
                Spacer()

                Button("Cancel") {
                    onCancel()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveError = nil

                    do {
                        try onSave(QuoteEditPresentationModel.saveRequest(draft: draft, books: books))
                    } catch let error as AppState.QuoteSaveError {
                        saveError = error
                    } catch {
                        assertionFailure("Unexpected quote save error: \(error)")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    private var title: String {
        QuoteEditPresentationModel.title(for: highlight)
    }

    private var matchedBook: Book? {
        QuoteEditPresentationModel.matchedBook(
            bookTitle: draft.bookTitle,
            author: draft.author,
            books: books
        )
    }

    private var canSave: Bool {
        QuoteEditPresentationModel.canSave(quoteText: draft.quoteText)
    }
}


#if TESTING
enum QuoteEditViewTestProbe {
    struct DraftSnapshot {
        let quoteText: String
        let bookTitle: String
        let author: String
        let location: String
    }

    static func title(for highlight: Highlight?) -> String {
        QuoteEditPresentationModel.title(for: highlight)
    }

    static func draftSnapshot(from highlight: Highlight?) -> DraftSnapshot {
        let draft = QuoteEditDraft(highlight: highlight)
        return DraftSnapshot(
            quoteText: draft.quoteText,
            bookTitle: draft.bookTitle,
            author: draft.author,
            location: draft.location
        )
    }

    static func canSave(quoteText: String) -> Bool {
        QuoteEditPresentationModel.canSave(quoteText: quoteText)
    }

    static func errorMessage(for error: AppState.QuoteSaveError) -> String {
        QuoteEditPresentationModel.errorMessage(for: error)
    }

    static func errorRecoverySuggestion(for error: AppState.QuoteSaveError) -> String? {
        QuoteEditPresentationModel.errorRecoverySuggestion(for: error)
    }

    static func matchedBookID(
        bookTitle: String,
        author: String,
        books: [Book]
    ) -> UUID? {
        QuoteEditPresentationModel.matchedBook(
            bookTitle: bookTitle,
            author: author,
            books: books
        )?.id
    }

    static func saveRequest(
        quoteText: String,
        bookTitle: String,
        author: String,
        location: String,
        books: [Book]
    ) -> QuoteEditSaveRequest {
        QuoteEditPresentationModel.saveRequest(
            draft: QuoteEditDraft(
                quoteText: quoteText,
                bookTitle: bookTitle,
                author: author,
                location: location
            ),
            books: books
        )
    }
}

#endif
