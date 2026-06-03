import Foundation
import GRDB
import OSLog

struct QuotesPagePayload: Equatable {
    let highlights: [Highlight]
    let totalMatchingHighlightCount: Int
}

struct QuotesFilterOptionsPayload: Equatable {
    let availableBookTitles: [String]
    let availableAuthors: [String]
}

enum DatabaseManager {
    enum HighlightUpdateError: Error, Equatable {
        case duplicateDedupeKey
    }

    enum DatabaseFailure: Error, Equatable, LocalizedError {
        case initializationFailed(String)
        case operationFailed(operation: String, message: String)

        var errorDescription: String? {
            switch self {
            case .initializationFailed(let message):
                return "Leaf could not open its quote database: \(message)"
            case .operationFailed(let operation, let message):
                return "Leaf could not \(operation): \(message)"
            }
        }
    }

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.marcuslo.KindleWall",
        category: "Database"
    )

    static let sharedResult: Result<DatabaseQueue, DatabaseFailure> = {
        do {
            return .success(try makeDatabaseQueue())
        } catch {
            let failure = DatabaseFailure.initializationFailed(userVisibleMessage(for: error))
            logger.error("Failed to initialize database: \(String(describing: error), privacy: .public)")
            return .failure(failure)
        }
    }()

    static var initializationFailureMessage: String? {
        guard case .failure(let failure) = sharedResult else {
            return nil
        }

        return failure.errorDescription
    }

    static func makeDatabaseQueue(databaseURL: URL? = nil) throws -> DatabaseQueue {
        let resolvedDatabaseURL: URL
        if let databaseURL {
            resolvedDatabaseURL = databaseURL
        } else {
            resolvedDatabaseURL = try makeDatabaseURL()
        }
        try createDirectoryIfNeeded(at: resolvedDatabaseURL.deletingLastPathComponent())

        var configuration = Configuration()
        configuration.busyMode = .timeout(5)
        configuration.foreignKeysEnabled = true

        let databaseQueue = try DatabaseQueue(path: resolvedDatabaseURL.path, configuration: configuration)
        try DatabaseSchema.initialize(in: databaseQueue)
        return databaseQueue
    }

    private static func sharedDatabaseQueue() throws -> DatabaseQueue {
        try sharedResult.get()
    }

    private static func makeDatabaseURL() throws -> URL {
        let appSupportURL = AppSupportPaths.kindleWallDirectory(fileManager: .default)
        return appSupportURL.appendingPathComponent("highlights.db", isDirectory: false)
    }

    private static func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func upsertBook(_ book: Book) -> UUID {
        do {
            return try sharedDatabaseQueue().write { database in
                try LibraryRepository.upsertBook(book, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "save book", error: error)
            return book.id
        }
    }

    static func insertHighlightIfNew(_ highlight: Highlight) {
        do {
            try sharedDatabaseQueue().write { database in
                _ = try LibraryRepository.insertHighlightIfNew(highlight, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "save highlight", error: error)
        }
    }

    static func setBookEnabled(id: UUID, enabled: Bool) {
        do {
            try sharedDatabaseQueue().write { database in
                try LibraryRepository.setBookEnabled(id: id, enabled: enabled, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "update book enabled state", error: error)
        }
    }

    static func setAllBooksEnabled(enabled: Bool) {
        do {
            try sharedDatabaseQueue().write { database in
                try LibraryRepository.setAllBooksEnabled(enabled: enabled, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "update all books enabled state", error: error)
        }
    }

    static func setHighlightEnabled(id: UUID, enabled: Bool) {
        do {
            try sharedDatabaseQueue().write { database in
                try LibraryRepository.setHighlightEnabled(id: id, enabled: enabled, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "update quote enabled state", error: error)
        }
    }

    static func updateHighlight(_ highlight: Highlight) throws {
        do {
            try sharedDatabaseQueue().write { database in
                try LibraryRepository.updateHighlight(highlight, database: database)
            }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw HighlightUpdateError.duplicateDedupeKey
        } catch {
            throw recoverableDatabaseFailure(operation: "save quote edits", error: error)
        }
    }

    static func pickNextHighlight() -> Highlight? {
        do {
            return try sharedDatabaseQueue().write { database in
                try LibraryRepository.pickNextHighlight(database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "pick next quote", error: error)
            return nil
        }
    }

    static func markHighlightShown(id: UUID) {
        do {
            try sharedDatabaseQueue().write { database in
                try LibraryRepository.markHighlightShown(id: id, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "mark quote as shown", error: error)
        }
    }

    static func deleteHighlight(id: UUID) -> LibrarySnapshot {
        deleteHighlights(ids: [id])
    }

    static func deleteHighlights(ids: [UUID]) -> LibrarySnapshot {
        let plan = makeBulkHighlightDeletionPlan(highlightIDs: ids)
        guard !plan.isEmpty else {
            do {
                return try sharedDatabaseQueue().read { database in
                    try LibraryRepository.makeLibrarySnapshot(database: database)
                }
            } catch {
                logRecoverableDatabaseError(operation: "delete quotes", error: error)
                return .empty
            }
        }

        return deleteHighlights(using: plan)
    }

    static func makeBulkHighlightDeletionPlan(highlightIDs: [UUID]) -> BulkHighlightDeletionPlan {
        do {
            return try sharedDatabaseQueue().read { database in
                try LibraryRepository.makeBulkHighlightDeletionPlan(highlightIDs: highlightIDs, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "prepare quote deletion", error: error)
            return BulkHighlightDeletionPlan(highlights: [])
        }
    }

    static func deleteHighlights(using plan: BulkHighlightDeletionPlan) -> LibrarySnapshot {
        do {
            return try sharedDatabaseQueue().write { database in
                try LibraryRepository.deleteHighlights(using: plan, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "delete quotes", error: error)
            return .empty
        }
    }

    static func makeBulkBookDeletionPlan(bookIDs: [UUID]) -> BulkBookDeletionPlan {
        do {
            return try sharedDatabaseQueue().read { database in
                try LibraryRepository.makeBulkBookDeletionPlan(bookIDs: bookIDs, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "prepare book deletion", error: error)
            return BulkBookDeletionPlan(bookIDs: [], linkedHighlights: [])
        }
    }

    static func deleteBooks(using plan: BulkBookDeletionPlan) -> LibrarySnapshot {
        do {
            return try sharedDatabaseQueue().write { database in
                try LibraryRepository.deleteBooks(using: plan, database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "delete books", error: error)
            return .empty
        }
    }

    static func persistImport(
        books: [Book],
        highlights: [Highlight]
    ) throws -> ImportPersistenceResult {
        do {
            return try sharedDatabaseQueue().write { database in
                try ImportRepository.persistImport(
                    books: books,
                    highlights: highlights,
                    database: database
                )
            }
        } catch {
            throw recoverableDatabaseFailure(operation: "save imported highlights", error: error)
        }
    }

    static func fetchAllBooks() -> [Book] {
        do {
            return try sharedDatabaseQueue().read { database in
                try LibraryRepository.fetchAllBooks(database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "load books", error: error)
            return []
        }
    }

    static func fetchAllHighlights(sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded) -> [Highlight] {
        do {
            return try QuoteRepository.fetchAllHighlights(sortedBy: sortMode, databaseQueue: try sharedDatabaseQueue())
        } catch {
            logRecoverableDatabaseError(operation: "load quotes", error: error)
            return []
        }
    }

    static func fetchHighlightsPage(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters(),
        sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded,
        limit: Int,
        offset: Int
    ) -> [Highlight] {
        do {
            return try QuoteRepository.fetchHighlightsPage(
                searchText: searchText,
                filters: filters,
                sortedBy: sortMode,
                limit: limit,
                offset: offset,
                databaseQueue: try sharedDatabaseQueue()
            )
        } catch {
            logRecoverableDatabaseError(operation: "load quote page", error: error)
            return []
        }
    }

    static func fetchHighlightPagePayload(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters(),
        sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded,
        limit: Int,
        offset: Int
    ) -> QuotesPagePayload {
        do {
            return try QuoteRepository.fetchHighlightPagePayload(
                searchText: searchText,
                filters: filters,
                sortedBy: sortMode,
                limit: limit,
                offset: offset,
                databaseQueue: try sharedDatabaseQueue()
            )
        } catch {
            logRecoverableDatabaseError(operation: "load quote page", error: error)
            return QuotesPagePayload(highlights: [], totalMatchingHighlightCount: 0)
        }
    }

    static func fetchHighlightFilterOptions(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> QuotesFilterOptionsPayload {
        do {
            return try QuoteRepository.fetchHighlightFilterOptions(
                searchText: searchText,
                filters: filters,
                databaseQueue: try sharedDatabaseQueue()
            )
        } catch {
            logRecoverableDatabaseError(operation: "load quote filters", error: error)
            return QuotesFilterOptionsPayload(availableBookTitles: [], availableAuthors: [])
        }
    }

    static func fetchAvailableHighlightBookTitles(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> [String] {
        do {
            return try QuoteRepository.fetchAvailableHighlightBookTitles(
                searchText: searchText,
                filters: filters,
                databaseQueue: try sharedDatabaseQueue()
            )
        } catch {
            logRecoverableDatabaseError(operation: "load book title filters", error: error)
            return []
        }
    }

    static func fetchAvailableHighlightAuthors(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> [String] {
        do {
            return try QuoteRepository.fetchAvailableHighlightAuthors(
                searchText: searchText,
                filters: filters,
                databaseQueue: try sharedDatabaseQueue()
            )
        } catch {
            logRecoverableDatabaseError(operation: "load author filters", error: error)
            return []
        }
    }

    static func countHighlights(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> Int {
        do {
            return try QuoteRepository.countHighlights(
                searchText: searchText,
                filters: filters,
                databaseQueue: try sharedDatabaseQueue()
            )
        } catch {
            logRecoverableDatabaseError(operation: "count quotes", error: error)
            return 0
        }
    }

    static func totalHighlightCount() -> Int {
        do {
            return try sharedDatabaseQueue().read { database in
                try LibraryRepository.totalHighlightCount(database: database)
            }
        } catch {
            logRecoverableDatabaseError(operation: "count saved highlights", error: error)
            return 0
        }
    }

    static func hasHighlightTombstone(
        bookTitle: String,
        author: String,
        location: String?,
        quoteText: String
    ) -> Bool {
        let quoteIdentityKey = QuoteIdentity.importStableQuoteIdentity(
            bookTitle: bookTitle,
            author: author,
            location: location,
            quoteText: quoteText
        )

        do {
            return try sharedDatabaseQueue().read { database in
                try LibraryRepository.hasHighlightTombstone(
                    quoteIdentityKey: quoteIdentityKey,
                    database: database
                )
            }
        } catch {
            logRecoverableDatabaseError(operation: "check deleted quote history", error: error)
            return false
        }
    }

    private static func recoverableDatabaseFailure(operation: String, error: Error) -> DatabaseFailure {
        if let failure = error as? DatabaseFailure {
            return failure
        }

        return .operationFailed(operation: operation, message: userVisibleMessage(for: error))
    }

    private static func logRecoverableDatabaseError(operation: String, error: Error) {
        let failure = recoverableDatabaseFailure(operation: operation, error: error)
        logger.error("\(failure.errorDescription ?? "Database operation failed", privacy: .public)")
    }

    private static func userVisibleMessage(for error: Error) -> String {
        let message = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return message.isEmpty ? String(describing: error) : message
    }
}
