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
    fputs("verify_t101_main failed: \(message)\n", stderr)
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

private func testReconciledSelectionDropsMissingBooksAndKeepsValidOnes() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
    let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!

    let reconciled = BooksListViewTestProbe.reconciledSelection(
        [firstID, secondID],
        validBookIDs: [secondID, thirdID]
    )

    assertEqual(reconciled, [secondID], "Expected book selection reconciliation to keep only still-valid IDs")
}

private func testBulkDeleteUsesExplicitSelectionAcrossFullLibrary() {
    let firstID = UUID(uuidString: "00000000-0000-0000-0000-000000000204")!
    let secondID = UUID(uuidString: "00000000-0000-0000-0000-000000000205")!
    let thirdID = UUID(uuidString: "00000000-0000-0000-0000-000000000206")!
    let books = [
        makeBook(id: firstID, title: "First", author: "Author 1", highlightCount: 3),
        makeBook(id: secondID, title: "Second", author: "Author 2", highlightCount: 5),
        makeBook(id: thirdID, title: "Third", author: "Author 3", highlightCount: 8)
    ]

    let deletedIDs = BooksListViewTestProbe.bulkDeleteBookIDs(
        from: books,
        selectedBookIDs: [firstID, thirdID]
    )

    assertEqual(
        deletedIDs,
        [firstID, thirdID],
        "Expected book bulk delete to operate only on explicitly selected rows"
    )
}

private func testBulkDeleteButtonDisabledState() {
    let selectedID = UUID(uuidString: "00000000-0000-0000-0000-000000000207")!

    assertTrue(
        BooksListViewTestProbe.bulkDeleteButtonDisabled(
            isEditing: false,
            selectedBookIDs: [selectedID]
        ),
        "Expected bulk-delete toolbar action to stay disabled outside book edit mode"
    )
    assertTrue(
        BooksListViewTestProbe.bulkDeleteButtonDisabled(
            isEditing: true,
            selectedBookIDs: []
        ),
        "Expected bulk-delete toolbar action to be disabled when no books are selected"
    )
    assertEqual(
        BooksListViewTestProbe.bulkDeleteButtonDisabled(
            isEditing: true,
            selectedBookIDs: [selectedID]
        ),
        false,
        "Expected bulk-delete toolbar action to enable once book edit mode has a selection"
    )
}

testReconciledSelectionDropsMissingBooksAndKeepsValidOnes()
testBulkDeleteUsesExplicitSelectionAcrossFullLibrary()
testBulkDeleteButtonDisabledState()

print("verify_t101_main passed")
