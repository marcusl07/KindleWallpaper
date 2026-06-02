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

    static let shared: DatabaseQueue = {
        do {
            let databaseURL = try makeDatabaseURL()
            try createDirectoryIfNeeded(at: databaseURL.deletingLastPathComponent())

            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            configuration.foreignKeysEnabled = true

            let databaseQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try DatabaseSchema.initialize(in: databaseQueue)
            return databaseQueue
        } catch {
            fatalError("Failed to initialize KindleWall database: \(error)")
        }
    }()

    private static func makeDatabaseURL() throws -> URL {
        let appSupportURL = AppSupportPaths.kindleWallDirectory(fileManager: .default)
        return appSupportURL.appendingPathComponent("highlights.db", isDirectory: false)
    }

    private static func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func upsertBook(_ book: Book) -> UUID {
        do {
            return try shared.write { database in
                try LibraryRepository.upsertBook(book, database: database)
            }
        } catch {
            fatalError("Failed to upsert book: \(error)")
        }
    }

    static func insertHighlightIfNew(_ highlight: Highlight) {
        do {
            try shared.write { database in
                _ = try LibraryRepository.insertHighlightIfNew(highlight, database: database)
            }
        } catch {
            fatalError("Failed to insert highlight: \(error)")
        }
    }

    static func setBookEnabled(id: UUID, enabled: Bool) {
        do {
            try shared.write { database in
                try LibraryRepository.setBookEnabled(id: id, enabled: enabled, database: database)
            }
        } catch {
            fatalError("Failed to set book enabled state: \(error)")
        }
    }

    static func setAllBooksEnabled(enabled: Bool) {
        do {
            try shared.write { database in
                try LibraryRepository.setAllBooksEnabled(enabled: enabled, database: database)
            }
        } catch {
            fatalError("Failed to set all books enabled state: \(error)")
        }
    }

    static func setHighlightEnabled(id: UUID, enabled: Bool) {
        do {
            try shared.write { database in
                try LibraryRepository.setHighlightEnabled(id: id, enabled: enabled, database: database)
            }
        } catch {
            fatalError("Failed to set highlight enabled state: \(error)")
        }
    }

    static func updateHighlight(_ highlight: Highlight) throws {
        do {
            try shared.write { database in
                try LibraryRepository.updateHighlight(highlight, database: database)
            }
        } catch let error as DatabaseError where error.extendedResultCode == .SQLITE_CONSTRAINT_UNIQUE {
            throw HighlightUpdateError.duplicateDedupeKey
        } catch {
            fatalError("Failed to update highlight: \(error)")
        }
    }

    static func pickNextHighlight() -> Highlight? {
        do {
            return try shared.write { database in
                try LibraryRepository.pickNextHighlight(database: database)
            }
        } catch {
            fatalError("Failed to pick next highlight: \(error)")
        }
    }

    static func markHighlightShown(id: UUID) {
        do {
            try shared.write { database in
                try LibraryRepository.markHighlightShown(id: id, database: database)
            }
        } catch {
            fatalError("Failed to mark highlight as shown: \(error)")
        }
    }

    static func deleteHighlight(id: UUID) -> LibrarySnapshot {
        deleteHighlights(ids: [id])
    }

    static func deleteHighlights(ids: [UUID]) -> LibrarySnapshot {
        let plan = makeBulkHighlightDeletionPlan(highlightIDs: ids)
        guard !plan.isEmpty else {
            do {
                return try shared.read { database in
                    try LibraryRepository.makeLibrarySnapshot(database: database)
                }
            } catch {
                fatalError("Failed to delete highlights: \(error)")
            }
        }

        return deleteHighlights(using: plan)
    }

    static func makeBulkHighlightDeletionPlan(highlightIDs: [UUID]) -> BulkHighlightDeletionPlan {
        do {
            return try shared.read { database in
                try LibraryRepository.makeBulkHighlightDeletionPlan(highlightIDs: highlightIDs, database: database)
            }
        } catch {
            fatalError("Failed to prepare bulk highlight deletion: \(error)")
        }
    }

    static func deleteHighlights(using plan: BulkHighlightDeletionPlan) -> LibrarySnapshot {
        do {
            return try shared.write { database in
                try LibraryRepository.deleteHighlights(using: plan, database: database)
            }
        } catch {
            fatalError("Failed to delete highlights: \(error)")
        }
    }

    static func makeBulkBookDeletionPlan(bookIDs: [UUID]) -> BulkBookDeletionPlan {
        do {
            return try shared.read { database in
                try LibraryRepository.makeBulkBookDeletionPlan(bookIDs: bookIDs, database: database)
            }
        } catch {
            fatalError("Failed to prepare bulk book deletion: \(error)")
        }
    }

    static func deleteBooks(using plan: BulkBookDeletionPlan) -> LibrarySnapshot {
        do {
            return try shared.write { database in
                try LibraryRepository.deleteBooks(using: plan, database: database)
            }
        } catch {
            fatalError("Failed to delete books: \(error)")
        }
    }

    static func persistImport(
        books: [Book],
        highlights: [Highlight]
    ) -> ImportPersistenceResult {
        do {
            return try shared.write { database in
                try ImportRepository.persistImport(
                    books: books,
                    highlights: highlights,
                    database: database
                )
            }
        } catch {
            fatalError("Failed to persist import: \(error)")
        }
    }

    static func fetchAllBooks() -> [Book] {
        do {
            return try shared.read { database in
                try LibraryRepository.fetchAllBooks(database: database)
            }
        } catch {
            fatalError("Failed to fetch all books: \(error)")
        }
    }

    static func fetchAllHighlights(sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded) -> [Highlight] {
        QuoteRepository.fetchAllHighlights(sortedBy: sortMode, databaseQueue: shared)
    }

    static func fetchHighlightsPage(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters(),
        sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded,
        limit: Int,
        offset: Int
    ) -> [Highlight] {
        QuoteRepository.fetchHighlightsPage(
            searchText: searchText,
            filters: filters,
            sortedBy: sortMode,
            limit: limit,
            offset: offset,
            databaseQueue: shared
        )
    }

    static func fetchHighlightPagePayload(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters(),
        sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded,
        limit: Int,
        offset: Int
    ) -> QuotesPagePayload {
        QuoteRepository.fetchHighlightPagePayload(
            searchText: searchText,
            filters: filters,
            sortedBy: sortMode,
            limit: limit,
            offset: offset,
            databaseQueue: shared
        )
    }

    static func fetchHighlightFilterOptions(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> QuotesFilterOptionsPayload {
        QuoteRepository.fetchHighlightFilterOptions(
            searchText: searchText,
            filters: filters,
            databaseQueue: shared
        )
    }

    static func fetchAvailableHighlightBookTitles(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> [String] {
        QuoteRepository.fetchAvailableHighlightBookTitles(
            searchText: searchText,
            filters: filters,
            databaseQueue: shared
        )
    }

    static func fetchAvailableHighlightAuthors(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> [String] {
        QuoteRepository.fetchAvailableHighlightAuthors(
            searchText: searchText,
            filters: filters,
            databaseQueue: shared
        )
    }

    static func countHighlights(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> Int {
        QuoteRepository.countHighlights(searchText: searchText, filters: filters, databaseQueue: shared)
    }

    static func totalHighlightCount() -> Int {
        do {
            return try shared.read { database in
                try LibraryRepository.totalHighlightCount(database: database)
            }
        } catch {
            fatalError("Failed to fetch total highlight count: \(error)")
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
            return try shared.read { database in
                try LibraryRepository.hasHighlightTombstone(
                    quoteIdentityKey: quoteIdentityKey,
                    database: database
                )
            }
        } catch {
            fatalError("Failed to check highlight tombstone: \(error)")
        }
    }
}
