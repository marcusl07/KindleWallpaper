import Foundation

#if canImport(GRDB)
import GRDB
#endif

struct ImportResult: Equatable {
    let newHighlightCount: Int
    let error: String?
}

struct ImportCoordinator {
    typealias ParseClippings = (URL) -> (highlights: [Highlight], books: [Book], parseErrorCount: Int)
    typealias UpsertBook = (Book) -> UUID
    typealias InsertHighlightIfNew = (Highlight) -> Void
    typealias TotalHighlightCount = () -> Int

    private let parseClippings: ParseClippings
    private let upsertBook: UpsertBook
    private let insertHighlightIfNew: InsertHighlightIfNew
    private let totalHighlightCount: TotalHighlightCount

    init(
        parseClippings: @escaping ParseClippings,
        upsertBook: @escaping UpsertBook,
        insertHighlightIfNew: @escaping InsertHighlightIfNew,
        totalHighlightCount: @escaping TotalHighlightCount
    ) {
        self.parseClippings = parseClippings
        self.upsertBook = upsertBook
        self.insertHighlightIfNew = insertHighlightIfNew
        self.totalHighlightCount = totalHighlightCount
    }

    func importFile(at url: URL) -> ImportResult {
        guard url.isFileURL else {
            return ImportResult(newHighlightCount: 0, error: "Import failed: URL is not a local file.")
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return ImportResult(
                newHighlightCount: 0,
                error: "Import failed: file does not exist at \(url.path)."
            )
        }

        let beforeCount = totalHighlightCount()
        let parsed = parseClippings(url)

        var persistedBookIDsByParsedID: [UUID: UUID] = [:]
        persistedBookIDsByParsedID.reserveCapacity(parsed.books.count)

        for book in parsed.books {
            let persistedBookID = upsertBook(book)
            persistedBookIDsByParsedID[book.id] = persistedBookID
        }

        var missingBookMappingCount = 0

        for highlight in parsed.highlights {
            guard let persistedBookID = persistedBookIDsByParsedID[highlight.bookId] else {
                missingBookMappingCount += 1
                continue
            }

            let persistedHighlight = Highlight(
                id: highlight.id,
                bookId: persistedBookID,
                quoteText: highlight.quoteText,
                bookTitle: highlight.bookTitle,
                author: highlight.author,
                location: highlight.location,
                dateAdded: highlight.dateAdded,
                lastShownAt: highlight.lastShownAt
            )
            insertHighlightIfNew(persistedHighlight)
        }

        let afterCount = totalHighlightCount()
        let newHighlightCount = max(0, afterCount - beforeCount)

        if missingBookMappingCount > 0 {
            return ImportResult(
                newHighlightCount: newHighlightCount,
                error: "Import completed with \(missingBookMappingCount) skipped highlight(s) due to missing book mappings."
            )
        }

        return ImportResult(newHighlightCount: newHighlightCount, error: nil)
    }
}

#if canImport(GRDB)
extension ImportCoordinator {
    static let live = ImportCoordinator(
        parseClippings: ClippingsParser.parseClippings(fileURL:),
        upsertBook: DatabaseManager.upsertBook,
        insertHighlightIfNew: DatabaseManager.insertHighlightIfNew,
        totalHighlightCount: DatabaseManager.totalHighlightCount
    )
}

func importFile(at url: URL) -> ImportResult {
    ImportCoordinator.live.importFile(at: url)
}
#endif
