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
    fputs("verify_t102_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func testBulkDeleteConfirmationTitleUsesExactCapturedCount() {
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationTitle(selectedCount: 1),
        "Delete 1 Quote?",
        "Expected single-quote bulk delete title to use the exact captured count"
    )
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationTitle(selectedCount: 3),
        "Delete 3 Quotes?",
        "Expected multi-quote bulk delete title to use the exact captured count"
    )
}

private func testBulkDeleteConfirmationMessageUsesExactCapturedCount() {
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationMessage(selectedCount: 1),
        "This will permanently remove 1 selected quote from your library.",
        "Expected single-quote bulk delete message to use the exact captured count"
    )
    assertEqual(
        QuotesListViewTestProbe.bulkDeleteConfirmationMessage(selectedCount: 4),
        "This will permanently remove 4 selected quotes from your library.",
        "Expected multi-quote bulk delete message to use the exact captured count"
    )
}

testBulkDeleteConfirmationTitleUsesExactCapturedCount()
testBulkDeleteConfirmationMessageUsesExactCapturedCount()

print("verify_t102_main passed")
