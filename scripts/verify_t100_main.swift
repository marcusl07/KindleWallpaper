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
    fputs("verify_t100_main failed: \(message)\n", stderr)
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
    dateAdded: Date? = nil
) -> Highlight {
    Highlight(
        id: id,
        bookId: nil,
        quoteText: quoteText,
        bookTitle: "Book \(quoteText)",
        author: "Author \(quoteText)",
        location: nil,
        dateAdded: dateAdded,
        lastShownAt: nil,
        isEnabled: true
    )
}

private func testReconciledSelectionDropsMissingRows() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000100")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!

    let reconciled = QuotesListViewTestProbe.reconciledSelection(
        [firstID, secondID],
        validHighlightIDs: [secondID, thirdID]
    )

    assertEqual(reconciled, [secondID], "Expected quote selection reconciliation to keep only still-valid IDs")
}

private func testBulkDeleteUsesExplicitSelectionAcrossFullLibrary() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
    let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000105")!
    let highlights = [
        makeHighlight(id: firstID, quoteText: "First"),
        makeHighlight(id: secondID, quoteText: "Second"),
        makeHighlight(id: thirdID, quoteText: "Third")
    ]

    let deletedIDs = QuotesListViewTestProbe.bulkDeleteHighlightIDs(
        from: highlights,
        selectedHighlightIDs: [firstID, thirdID]
    )

    assertEqual(
        deletedIDs,
        [firstID, thirdID],
        "Expected quote bulk delete to operate only on explicitly selected rows"
    )
}

private func testBulkDeleteButtonDisabledState() {
    let selectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000106")!

    assertTrue(
        QuotesListViewTestProbe.bulkDeleteButtonDisabled(
            isEditing: false,
            selectedHighlightIDs: [selectedID]
        ),
        "Expected bulk-delete toolbar action to stay disabled outside edit mode"
    )
    assertTrue(
        QuotesListViewTestProbe.bulkDeleteButtonDisabled(
            isEditing: true,
            selectedHighlightIDs: []
        ),
        "Expected bulk-delete toolbar action to be disabled when no rows are selected"
    )
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteButtonDisabled(
            isEditing: true,
            selectedHighlightIDs: [selectedID]
        ),
        false,
        "Expected bulk-delete toolbar action to enable once edit mode has a selection"
    )
}

private func testResultCountSummaryIncludesSelectionCountDuringEditMode() {
    let summary = QuotesListViewTestProbe.resultCountSummary(
        displayedCount: 2,
        totalCount: 5,
        hasActiveQuery: true,
        isEditing: true,
        selectedCount: 3
    )

    assertEqual(
        summary,
        "2 of 5 quotes • 3 selected",
        "Expected quote edit mode summary to include the explicit selected count"
    )
}

testReconciledSelectionDropsMissingRows()
testBulkDeleteUsesExplicitSelectionAcrossFullLibrary()
testBulkDeleteButtonDisabledState()
testResultCountSummaryIncludesSelectionCountDuringEditMode()

print("verify_t100_main passed")
