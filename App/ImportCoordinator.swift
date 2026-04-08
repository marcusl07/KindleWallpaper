import Foundation

#if canImport(GRDB)
import GRDB
#endif

struct ImportResult: Equatable {
    let newHighlightCount: Int
    let error: String?
    let parseWarningCount: Int
    let skippedEntryCount: Int
    let warningMessages: [String]
    let librarySnapshot: LibrarySnapshot?
}

struct ImportPersistenceResult: Equatable {
    let newHighlightCount: Int
    let missingBookMappingCount: Int
    let librarySnapshot: LibrarySnapshot
}

struct ImportCoordinator {
    typealias ParseClippings = (URL) -> ClippingsParser.ParseResult
    typealias UpsertBook = (Book) -> UUID
    typealias HighlightHasTombstone = (Highlight) -> Bool
    typealias InsertHighlightIfNew = (Highlight) -> Void
    typealias TotalHighlightCount = () -> Int
    typealias PersistImport = ([Book], [Highlight]) -> ImportPersistenceResult

    private let parseClippings: ParseClippings
    private let upsertBook: UpsertBook
    private let highlightHasTombstone: HighlightHasTombstone
    private let insertHighlightIfNew: InsertHighlightIfNew
    private let totalHighlightCount: TotalHighlightCount
    private let persistImport: PersistImport?

    init(
        parseClippings: @escaping ParseClippings,
        upsertBook: @escaping UpsertBook,
        highlightHasTombstone: @escaping HighlightHasTombstone = { _ in false },
        insertHighlightIfNew: @escaping InsertHighlightIfNew,
        totalHighlightCount: @escaping TotalHighlightCount,
        persistImport: PersistImport? = nil
    ) {
        self.parseClippings = parseClippings
        self.upsertBook = upsertBook
        self.highlightHasTombstone = highlightHasTombstone
        self.insertHighlightIfNew = insertHighlightIfNew
        self.totalHighlightCount = totalHighlightCount
        self.persistImport = persistImport
    }

    func importFile(at url: URL) -> ImportResult {
        guard url.isFileURL else {
            return ImportResult(
                newHighlightCount: 0,
                error: "Import failed: URL is not a local file.",
                parseWarningCount: 0,
                skippedEntryCount: 0,
                warningMessages: [],
                librarySnapshot: nil
            )
        }

        guard FileManager.default.fileExists(atPath: url.path) else {
            return ImportResult(
                newHighlightCount: 0,
                error: "Import failed: file does not exist at \(url.path).",
                parseWarningCount: 0,
                skippedEntryCount: 0,
                warningMessages: [],
                librarySnapshot: nil
            )
        }

        let parsed = parseClippings(url)

        if let error = parsed.error {
            return ImportResult(
                newHighlightCount: 0,
                error: error,
                parseWarningCount: parsed.parseErrorCount,
                skippedEntryCount: parsed.skippedEntryCount,
                warningMessages: parsed.warningMessages,
                librarySnapshot: nil
            )
        }

        if let persistImport {
            let persistenceResult = persistImport(parsed.books, parsed.highlights)
            return makeImportResult(
                newHighlightCount: persistenceResult.newHighlightCount,
                missingBookMappingCount: persistenceResult.missingBookMappingCount,
                parseWarningCount: parsed.parseErrorCount,
                skippedEntryCount: parsed.skippedEntryCount,
                warningMessages: parsed.warningMessages,
                librarySnapshot: persistenceResult.librarySnapshot
            )
        }

        let beforeCount = totalHighlightCount()

        var persistedBookIDsByParsedID: [UUID: UUID] = [:]
        persistedBookIDsByParsedID.reserveCapacity(parsed.books.count)

        for book in parsed.books {
            let persistedBookID = upsertBook(book)
            persistedBookIDsByParsedID[book.id] = persistedBookID
        }

        var missingBookMappingCount = 0

        for highlight in parsed.highlights {
            guard
                let parsedBookID = highlight.bookId,
                let persistedBookID = persistedBookIDsByParsedID[parsedBookID]
            else {
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
                lastShownAt: highlight.lastShownAt,
                isEnabled: highlight.isEnabled
            )

            guard highlightHasTombstone(persistedHighlight) == false else {
                continue
            }

            insertHighlightIfNew(persistedHighlight)
        }

        let afterCount = totalHighlightCount()
        let newHighlightCount = max(0, afterCount - beforeCount)

        return makeImportResult(
            newHighlightCount: newHighlightCount,
            missingBookMappingCount: missingBookMappingCount,
            parseWarningCount: parsed.parseErrorCount,
            skippedEntryCount: parsed.skippedEntryCount,
            warningMessages: parsed.warningMessages,
            librarySnapshot: nil
        )
    }

    private func makeImportResult(
        newHighlightCount: Int,
        missingBookMappingCount: Int,
        parseWarningCount: Int,
        skippedEntryCount: Int,
        warningMessages: [String],
        librarySnapshot: LibrarySnapshot?
    ) -> ImportResult {
        let error: String?
        if missingBookMappingCount > 0 {
            error = "Import completed with \(missingBookMappingCount) skipped highlight(s) due to missing book mappings."
        } else {
            error = nil
        }

        return ImportResult(
            newHighlightCount: newHighlightCount,
            error: error,
            parseWarningCount: parseWarningCount,
            skippedEntryCount: skippedEntryCount,
            warningMessages: warningMessages,
            librarySnapshot: librarySnapshot
        )
    }
}

#if canImport(GRDB)
extension ImportCoordinator {
    static let live = ImportCoordinator(
        parseClippings: ClippingsParser.parseClippings(fileURL:),
        upsertBook: { $0.id },
        insertHighlightIfNew: { _ in },
        totalHighlightCount: { 0 },
        persistImport: DatabaseManager.persistImport(books:highlights:)
    )
}

func importFile(at url: URL) -> ImportResult {
    ImportCoordinator.live.importFile(at: url)
}
#endif
