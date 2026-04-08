import Foundation

enum WallpaperSetter {
    enum RestoreOutcome: Equatable {
        case fullRestore
        case partialRestore
        case noStoredWallpapers
        case noConnectedScreens
        case applyFailure
    }

    struct ResolvedScreen<Screen> {
        let screen: Screen
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
        let backingScaleFactor: CGFloat
        let originX: Int
        let originY: Int

        init(
            screen: Screen,
            identifier: String,
            pixelWidth: Int = 0,
            pixelHeight: Int = 0,
            backingScaleFactor: CGFloat = 1,
            originX: Int = 0,
            originY: Int = 0
        ) {
            self.screen = screen
            self.identifier = identifier
            self.pixelWidth = pixelWidth
            self.pixelHeight = pixelHeight
            self.backingScaleFactor = backingScaleFactor
            self.originX = originX
            self.originY = originY
        }
    }

    typealias CurrentDesktopImageURL<Screen> = (Screen) -> URL?

    @discardableResult
    static func applySharedWallpaper<Screen>(
        imageURL: URL,
        resolvedScreens: [ResolvedScreen<Screen>],
        currentDesktopImageURL: CurrentDesktopImageURL<Screen>? = nil,
        setDesktopImage: (URL, Screen) throws -> Void
    ) rethrows -> Int {
        0
    }
}

private func fail(_ message: String) -> Never {
    fputs("verify_t104_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func assertTrue(_ value: Bool, _ message: String) {
    if !value {
        fail(message)
    }
}

private func makeHighlight(
    id: UUID,
    quoteText: String,
    bookTitle: String = "Book",
    author: String = "Author",
    location: String? = nil,
    dateAdded: Date? = nil
) -> Highlight {
    Highlight(
        id: id,
        bookId: nil,
        quoteText: quoteText,
        bookTitle: bookTitle,
        author: author,
        location: location,
        dateAdded: dateAdded,
        lastShownAt: nil,
        isEnabled: true
    )
}

private func makeBook(
    id: UUID,
    title: String,
    author: String,
    isEnabled: Bool = true,
    highlightCount: Int = 0
) -> Book {
    Book(
        id: id,
        title: title,
        author: author,
        isEnabled: isEnabled,
        highlightCount: highlightCount
    )
}

private func makeTempFileURL() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kindlewall-t104-\(UUID().uuidString).txt")
    try? "fixture".write(to: url, atomically: true, encoding: .utf8)
    return url
}

private func removeTempFile(at url: URL) {
    try? FileManager.default.removeItem(at: url)
}

private func testImportCoordinatorSuppressesReimportWhenTombstoneIdentityMatchesNormalizedFields() {
    let tempFileURL = makeTempFileURL()
    defer { removeTempFile(at: tempFileURL) }

    let parsedBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
    let persistedBookID = UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
    let parsedHighlight = Highlight(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!,
        bookId: parsedBookID,
        quoteText: "  Keep   going. ",
        bookTitle: " The Long Road ",
        author: " Jane Doe ",
        location: "   ",
        dateAdded: nil,
        lastShownAt: nil,
        isEnabled: true
    )
    let tombstoneIdentities: Set<String> = [
        ImportStableQuoteIdentityKeyBuilder.makeKey(
            bookTitle: "the long road",
            author: "jane doe",
            location: nil,
            quoteText: "keep going."
        )
    ]

    var insertedHighlights: [Highlight] = []
    var tombstoneChecks: [Highlight] = []

    let coordinator = ImportCoordinator(
        parseClippings: { _ in
            ClippingsParser.ParseResult(
                highlights: [parsedHighlight],
                books: [makeBook(id: parsedBookID, title: "The Long Road", author: "Jane Doe", highlightCount: 1)],
                parseErrorCount: 0,
                skippedEntryCount: 0,
                warningMessages: [],
                error: nil
            )
        },
        upsertBook: { _ in persistedBookID },
        highlightHasTombstone: { highlight in
            tombstoneChecks.append(highlight)
            let identity = ImportStableQuoteIdentityKeyBuilder.makeKey(
                bookTitle: highlight.bookTitle,
                author: highlight.author,
                location: highlight.location,
                quoteText: highlight.quoteText
            )
            return tombstoneIdentities.contains(identity)
        },
        insertHighlightIfNew: { insertedHighlights.append($0) },
        totalHighlightCount: { insertedHighlights.count }
    )

    let result = coordinator.importFile(at: tempFileURL)

    assertEqual(result.newHighlightCount, 0, "Expected tombstoned re-import to add zero highlights")
    assertEqual(insertedHighlights.count, 0, "Expected tombstoned re-import to skip insertion")
    assertEqual(tombstoneChecks.count, 1, "Expected tombstone matching to run for each persisted highlight candidate")
    assertEqual(tombstoneChecks.first?.bookId, persistedBookID, "Expected tombstone suppression to evaluate the persisted book mapping")
    assertEqual(result.error, nil, "Expected tombstoned re-import suppression to be a non-error path")
}

private func testQuoteSelectionReconciliationDropsDeletedRowsAndDoesNotSelectNewImports() {
    let retainedID = UUID(uuidString: "00000000-0000-0000-0000-000000000404")!
    let deletedID = UUID(uuidString: "00000000-0000-0000-0000-000000000405")!
    let importedID = UUID(uuidString: "00000000-0000-0000-0000-000000000406")!

    let reconciled = QuotesListViewTestProbe.reconciledSelection(
        [retainedID, deletedID],
        validHighlightIDs: [retainedID, importedID]
    )

    assertEqual(
        reconciled,
        [retainedID],
        "Expected quote selection reconciliation to drop deleted rows while keeping existing selected rows only"
    )
}

private func testBookSelectionReconciliationDropsDeletedRowsAndDoesNotSelectNewImports() {
    let retainedID = UUID(uuidString: "00000000-0000-0000-0000-000000000407")!
    let deletedID = UUID(uuidString: "00000000-0000-0000-0000-000000000408")!
    let importedID = UUID(uuidString: "00000000-0000-0000-0000-000000000409")!

    let reconciled = BooksListViewTestProbe.reconciledSelection(
        [retainedID, deletedID],
        validBookIDs: [retainedID, importedID]
    )

    assertEqual(
        reconciled,
        [retainedID],
        "Expected book selection reconciliation to drop deleted rows while keeping existing selected rows only"
    )
}

private func testBulkDeleteDisabledStateStaysDisabledForEmptySelections() {
    assertTrue(
        QuotesListViewTestProbe.bulkDeleteButtonDisabled(
            isEditing: true,
            selectedHighlightIDs: []
        ),
        "Expected quote bulk-delete action to remain disabled for an empty edit-mode selection"
    )
    assertTrue(
        BooksListViewTestProbe.bulkDeleteButtonDisabled(
            isEditing: true,
            selectedBookIDs: []
        ),
        "Expected book bulk-delete action to remain disabled for an empty edit-mode selection"
    )
}

private func testBulkDeleteConfirmationCountsStayExact() {
    let bookPlan = BulkBookDeletionPlan(
        bookIDs: [
            UUID(uuidString: "00000000-0000-0000-0000-000000000410")!,
            UUID(uuidString: "00000000-0000-0000-0000-000000000411")!
        ],
        linkedHighlights: [
            BulkBookDeletionLinkedHighlight(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000412")!,
                bookTitle: "Book A",
                author: "Author A",
                location: "Loc 1",
                quoteText: "Quote A"
            ),
            BulkBookDeletionLinkedHighlight(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000413")!,
                bookTitle: "Book B",
                author: "Author B",
                location: nil,
                quoteText: "Quote B"
            ),
            BulkBookDeletionLinkedHighlight(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000414")!,
                bookTitle: "Book C",
                author: "Author C",
                location: nil,
                quoteText: "Quote C"
            )
        ]
    )

    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationTitle(selectedCount: 5),
        "Delete 5 Quotes?",
        "Expected quote bulk-delete title to keep the captured count"
    )
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationMessage(selectedCount: 5),
        "This will permanently remove 5 selected quotes from your library.",
        "Expected quote bulk-delete message to keep the captured count"
    )
    assertEqual(
        BooksListViewTestProbe.bulkDeleteConfirmationTitle(plan: bookPlan),
        "Delete 2 Books?",
        "Expected book bulk-delete title to keep the captured book count"
    )
    assertEqual(
        BooksListViewTestProbe.bulkDeleteConfirmationMessage(plan: bookPlan),
        "This will permanently remove 2 selected books and delete 3 linked quotes from your library.",
        "Expected book bulk-delete message to keep the captured book and quote counts"
    )
}

testImportCoordinatorSuppressesReimportWhenTombstoneIdentityMatchesNormalizedFields()
testQuoteSelectionReconciliationDropsDeletedRowsAndDoesNotSelectNewImports()
testBookSelectionReconciliationDropsDeletedRowsAndDoesNotSelectNewImports()
testBulkDeleteDisabledStateStaysDisabledForEmptySelections()
testBulkDeleteConfirmationCountsStayExact()

print("verify_t104_main passed")
