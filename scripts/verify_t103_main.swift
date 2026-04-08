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
    fputs("verify_t103_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func makePlan(bookCount: Int, linkedHighlightCount: Int) -> BulkBookDeletionPlan {
    let bookIDs = (0..<bookCount).map { offset in
        UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 300 + offset))!
    }
    let linkedHighlights = (0..<linkedHighlightCount).map { offset in
        BulkBookDeletionLinkedHighlight(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", 400 + offset))!,
            bookTitle: "Book \(offset)",
            author: "Author \(offset)",
            location: nil,
            quoteText: "Quote \(offset)"
        )
    }

    return BulkBookDeletionPlan(bookIDs: bookIDs, linkedHighlights: linkedHighlights)
}

private func testBulkDeleteConfirmationTitleUsesExactCapturedBookCount() {
    assertEqual(
        BooksListViewTestProbe.bulkDeleteConfirmationTitle(plan: makePlan(bookCount: 1, linkedHighlightCount: 7)),
        "Delete 1 Book?",
        "Expected single-book bulk delete title to use the exact captured book count"
    )
    assertEqual(
        BooksListViewTestProbe.bulkDeleteConfirmationTitle(plan: makePlan(bookCount: 3, linkedHighlightCount: 1)),
        "Delete 3 Books?",
        "Expected multi-book bulk delete title to use the exact captured book count"
    )
}

private func testBulkDeleteConfirmationMessageUsesExactCapturedCounts() {
    assertEqual(
        BooksListViewTestProbe.bulkDeleteConfirmationMessage(plan: makePlan(bookCount: 1, linkedHighlightCount: 1)),
        "This will permanently remove 1 selected book and delete 1 linked quote from your library.",
        "Expected single-book confirmation message to use the exact captured book and quote counts"
    )
    assertEqual(
        BooksListViewTestProbe.bulkDeleteConfirmationMessage(plan: makePlan(bookCount: 2, linkedHighlightCount: 5)),
        "This will permanently remove 2 selected books and delete 5 linked quotes from your library.",
        "Expected multi-book confirmation message to use the exact captured book and quote counts"
    )
}

testBulkDeleteConfirmationTitleUsesExactCapturedBookCount()
testBulkDeleteConfirmationMessageUsesExactCapturedCounts()

print("verify_t103_main passed")
