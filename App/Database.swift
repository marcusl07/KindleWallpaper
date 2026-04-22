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

    private static let tombstoneInsertBatchRowLimit = 400
    private static let deleteSelectionBatchRowLimit = 400
    private static let importPreflightBatchRowLimit = 400
    private static let importBookUpsertBatchRowLimit = 200
    private static let importHighlightInsertBatchRowLimit = 90
    private static let quotesPerformanceSignposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.marcuslo.KindleWall",
        category: "QuotesPerformance"
    )

    private struct ImportHighlightInsertRow {
        let highlight: Highlight
        let quoteIdentityKey: String
        let dedupeKey: String
    }

    static let shared: DatabaseQueue = {
        do {
            let databaseURL = try makeDatabaseURL()
            try createDirectoryIfNeeded(at: databaseURL.deletingLastPathComponent())

            var configuration = Configuration()
            configuration.busyMode = .timeout(5)
            configuration.foreignKeysEnabled = true

            let databaseQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
            try initializeSchema(in: databaseQueue)
            return databaseQueue
        } catch {
            fatalError("Failed to initialize KindleWall database: \(error)")
        }
    }()

    private static let createBooksTableSQL = """
    CREATE TABLE IF NOT EXISTS books (
        id          TEXT PRIMARY KEY,
        title       TEXT NOT NULL,
        author      TEXT NOT NULL,
        isEnabled   INTEGER NOT NULL DEFAULT 1,
        UNIQUE(title, author)
    );
    """

    private static let createHighlightsTableSQL = """
    CREATE TABLE IF NOT EXISTS highlights (
        id          TEXT PRIMARY KEY,
        bookId      TEXT,
        quoteText   TEXT NOT NULL,
        bookTitle   TEXT NOT NULL,
        author      TEXT NOT NULL,
        location    TEXT,
        dateAdded   TEXT,
        lastShownAt TEXT,
        isEnabled   INTEGER NOT NULL DEFAULT 1,
        dedupeKey   TEXT NOT NULL UNIQUE
    );
    """

    private static let createHighlightsBookIDIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_bookId
    ON highlights(bookId);
    """

    private static let createHighlightsBookIDLastShownAtIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_bookId_lastShownAt
    ON highlights(bookId, lastShownAt);
    """

    private static let createHighlightsBookTitleIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_bookTitle_nocase
    ON highlights(bookTitle COLLATE NOCASE);
    """

    private static let createHighlightsAuthorIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_author_nocase
    ON highlights(author COLLATE NOCASE);
    """

    private static let createHighlightsDateAddedIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_dateAdded
    ON highlights(dateAdded);
    """

    private static let createHighlightsAlphabeticalSortIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_alphabetical_sort
    ON highlights(
        bookTitle COLLATE NOCASE,
        author COLLATE NOCASE,
        quoteText COLLATE NOCASE,
        id
    );
    """

    private static let createHighlightsMostRecentSortIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_most_recent_sort
    ON highlights(
        dateAdded DESC,
        bookTitle COLLATE NOCASE,
        author COLLATE NOCASE,
        quoteText COLLATE NOCASE,
        id
    );
    """

    private static let createHighlightsMostRecentNonNullSortIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_most_recent_non_null_sort
    ON highlights(
        dateAdded DESC,
        bookTitle COLLATE NOCASE,
        author COLLATE NOCASE,
        quoteText COLLATE NOCASE,
        id
    )
    WHERE dateAdded IS NOT NULL;
    """

    private static let createHighlightTombstonesTableSQL = """
    CREATE TABLE IF NOT EXISTS highlight_tombstones (
        quoteIdentityKey TEXT PRIMARY KEY,
        deletedAt        TEXT NOT NULL
    );
    """

    private static let activeHighlightsPredicateSQL = """
    (bookId IS NULL OR bookId IN (SELECT id FROM books WHERE isEnabled = 1))
      AND isEnabled = 1
    """

    private static let normalizedBookTitleExpressionSQL = """
    CASE
        WHEN TRIM(bookTitle) = '' THEN 'Unknown Book'
        ELSE TRIM(bookTitle)
    END
    """

    private static let normalizedAuthorExpressionSQL = """
    CASE
        WHEN TRIM(author) = '' THEN 'Unknown Author'
        ELSE TRIM(author)
    END
    """

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let migrator: DatabaseMigrator = {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("createInitialSchema") { database in
            try database.execute(sql: createBooksTableSQL)
            try database.execute(sql: createHighlightsTableSQL)
            try createHighlightsIndexes(in: database)
            try database.execute(sql: createHighlightTombstonesTableSQL)
        }

        migrator.registerMigration("addHighlightsIsEnabled") { database in
            guard try !tableColumnNames(in: "highlights", database: database).contains("isEnabled") else {
                return
            }

            try database.execute(
                sql: """
                ALTER TABLE highlights
                ADD COLUMN isEnabled INTEGER NOT NULL DEFAULT 1
                """
            )
        }

        migrator.registerMigration("makeHighlightsBookIDNullable") { database in
            let columnInfoRows = try Row.fetchAll(database, sql: "PRAGMA table_info(highlights)")
            guard
                let bookIDColumn = columnInfoRows.first(where: { ($0["name"] as String?) == "bookId" })
            else {
                return
            }

            let isBookIDNotNull: Int = bookIDColumn["notnull"]
            guard isBookIDNotNull != 0 else {
                return
            }

            try database.execute(
                sql: """
                CREATE TABLE highlights_migrated (
                    id          TEXT PRIMARY KEY,
                    bookId      TEXT,
                    quoteText   TEXT NOT NULL,
                    bookTitle   TEXT NOT NULL,
                    author      TEXT NOT NULL,
                    location    TEXT,
                    dateAdded   TEXT,
                    lastShownAt TEXT,
                    isEnabled   INTEGER NOT NULL DEFAULT 1,
                    dedupeKey   TEXT NOT NULL UNIQUE
                );
                """
            )

            try database.execute(
                sql: """
                INSERT INTO highlights_migrated (
                    id,
                    bookId,
                    quoteText,
                    bookTitle,
                    author,
                    location,
                    dateAdded,
                    lastShownAt,
                    isEnabled,
                    dedupeKey
                )
                SELECT
                    id,
                    bookId,
                    quoteText,
                    bookTitle,
                    author,
                    location,
                    dateAdded,
                    lastShownAt,
                    isEnabled,
                    dedupeKey
                FROM highlights
                """
            )

            try database.execute(sql: "DROP TABLE highlights")
            try database.execute(sql: "ALTER TABLE highlights_migrated RENAME TO highlights")
            try createHighlightsIndexes(in: database)
        }

        migrator.registerMigration("createHighlightTombstones") { database in
            try database.execute(sql: createHighlightTombstonesTableSQL)
        }

        migrator.registerMigration("addHighlightSortIndexes") { database in
            try database.execute(sql: createHighlightsBookTitleIndexSQL)
            try database.execute(sql: createHighlightsAuthorIndexSQL)
            try database.execute(sql: createHighlightsDateAddedIndexSQL)
        }

        migrator.registerMigration("addHighlightPagingIndexes") { database in
            try createHighlightsPageIndexes(in: database)
        }

        migrator.registerMigration("addHighlightMostRecentNonNullSortIndex") { database in
            try database.execute(sql: createHighlightsMostRecentNonNullSortIndexSQL)
        }

        return migrator
    }()

    private static func makeDatabaseURL() throws -> URL {
        let appSupportURL = AppSupportPaths.kindleWallDirectory(fileManager: .default)
        return appSupportURL.appendingPathComponent("highlights.db", isDirectory: false)
    }

    private static func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func initializeSchema(in databaseQueue: DatabaseQueue) throws {
        try migrator.migrate(databaseQueue)
    }

    private static func createHighlightsIndexes(in database: Database) throws {
        try database.execute(sql: createHighlightsBookIDIndexSQL)
        try database.execute(sql: createHighlightsBookIDLastShownAtIndexSQL)
        try database.execute(sql: createHighlightsBookTitleIndexSQL)
        try database.execute(sql: createHighlightsAuthorIndexSQL)
        try database.execute(sql: createHighlightsDateAddedIndexSQL)
        try createHighlightsPageIndexes(in: database)
    }

    private static func createHighlightsPageIndexes(in database: Database) throws {
        try database.execute(sql: createHighlightsAlphabeticalSortIndexSQL)
        try database.execute(sql: createHighlightsMostRecentSortIndexSQL)
        try database.execute(sql: createHighlightsMostRecentNonNullSortIndexSQL)
    }

    private static func tableColumnNames(in tableName: String, database: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(database, sql: "PRAGMA table_info(\(tableName))")
        return Set(rows.compactMap { row in
            row["name"] as String?
        })
    }

    static func upsertBook(_ book: Book) -> UUID {
        do {
            return try shared.write { database in
                try upsertBook(book, database: database)
            }
        } catch {
            fatalError("Failed to upsert book: \(error)")
        }
    }

    static func insertHighlightIfNew(_ highlight: Highlight) {
        do {
            try shared.write { database in
                _ = try insertHighlightIfNew(highlight, database: database)
            }
        } catch {
            fatalError("Failed to insert highlight: \(error)")
        }
    }

    static func setBookEnabled(id: UUID, enabled: Bool) {
        do {
            try shared.write { database in
                try database.execute(
                    sql: """
                    UPDATE books
                    SET isEnabled = ?
                    WHERE id = ?
                    """,
                    arguments: [enabled ? 1 : 0, id.uuidString]
                )

                if enabled {
                    try database.execute(
                        sql: """
                        UPDATE highlights
                        SET lastShownAt = NULL
                        WHERE bookId = ?
                        """,
                        arguments: [id.uuidString]
                    )
                }
            }
        } catch {
            fatalError("Failed to set book enabled state: \(error)")
        }
    }

    static func setAllBooksEnabled(enabled: Bool) {
        do {
            try shared.write { database in
                if enabled {
                    try database.execute(
                        sql: """
                        UPDATE highlights
                        SET lastShownAt = NULL
                        WHERE bookId IN (
                            SELECT id
                            FROM books
                            WHERE isEnabled = 0
                        )
                        """
                    )

                    try database.execute(
                        sql: """
                        UPDATE books
                        SET isEnabled = 1
                        WHERE isEnabled = 0
                        """
                    )
                } else {
                    try database.execute(
                        sql: """
                        UPDATE books
                        SET isEnabled = 0
                        WHERE isEnabled = 1
                        """
                    )
                }
            }
        } catch {
            fatalError("Failed to set all books enabled state: \(error)")
        }
    }

    static func setHighlightEnabled(id: UUID, enabled: Bool) {
        do {
            try shared.write { database in
                try database.execute(
                    sql: """
                    UPDATE highlights
                    SET isEnabled = ?
                    WHERE id = ?
                    """,
                    arguments: [enabled ? 1 : 0, id.uuidString]
                )

                if enabled {
                    try database.execute(
                        sql: """
                        UPDATE highlights
                        SET lastShownAt = NULL
                        WHERE id = ?
                        """,
                        arguments: [id.uuidString]
                    )
                }
            }
        } catch {
            fatalError("Failed to set highlight enabled state: \(error)")
        }
    }

    static func updateHighlight(_ highlight: Highlight) throws {
        do {
            try shared.write { database in
                try database.execute(
                    sql: """
                    UPDATE highlights
                    SET bookId = ?,
                        quoteText = ?,
                        bookTitle = ?,
                        author = ?,
                        location = ?,
                        dedupeKey = ?
                    WHERE id = ?
                    """,
                    arguments: [
                        highlight.bookId?.uuidString,
                        highlight.quoteText,
                        highlight.bookTitle,
                        highlight.author,
                        highlight.location,
                        computeDedupeKey(for: highlight),
                        highlight.id.uuidString
                    ]
                )
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
                let activePoolCount = try Int.fetchOne(
                    database,
                    sql: """
                    SELECT COUNT(*)
                    FROM highlights
                    WHERE \(activeHighlightsPredicateSQL)
                    """
                ) ?? 0

                guard activePoolCount > 0 else {
                    return nil
                }

                var eligibleCount = try Int.fetchOne(
                    database,
                    sql: """
                    SELECT COUNT(*)
                    FROM highlights
                    WHERE \(activeHighlightsPredicateSQL)
                      AND lastShownAt IS NULL
                    """
                ) ?? 0

                if eligibleCount == 0 {
                    try database.execute(
                        sql: """
                        UPDATE highlights
                        SET lastShownAt = NULL
                        WHERE \(activeHighlightsPredicateSQL)
                        """
                    )

                    eligibleCount = try Int.fetchOne(
                        database,
                        sql: """
                        SELECT COUNT(*)
                        FROM highlights
                        WHERE \(activeHighlightsPredicateSQL)
                          AND lastShownAt IS NULL
                        """
                    ) ?? 0
                }

                guard eligibleCount > 0 else {
                    return nil
                }

                let randomOffset = Int.random(in: 0..<eligibleCount)
                guard let row = try Row.fetchOne(
                    database,
                    sql: """
                    SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled
                    FROM highlights
                    WHERE \(activeHighlightsPredicateSQL)
                      AND lastShownAt IS NULL
                    LIMIT 1 OFFSET ?
                    """,
                    arguments: [randomOffset]
                ) else {
                    fatalError("Failed to fetch highlight at random offset \(randomOffset)")
                }

                return highlight(from: row)
            }
        } catch {
            fatalError("Failed to pick next highlight: \(error)")
        }
    }

    static func markHighlightShown(id: UUID) {
        do {
            try shared.write { database in
                try database.execute(
                    sql: """
                    UPDATE highlights
                    SET lastShownAt = ?
                    WHERE id = ?
                    """,
                    arguments: [iso8601Formatter.string(from: Date()), id.uuidString]
                )
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
                    try makeLibrarySnapshot(database: database)
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
                let capturedLiveHighlights = try fetchLiveHighlights(matchingIDs: highlightIDs, database: database)
                return BulkHighlightDeletionPlan(
                    highlights: capturedLiveHighlights.map { highlight in
                        BulkHighlightDeletionTarget(
                            id: highlight.id,
                            bookTitle: highlight.bookTitle,
                            author: highlight.author,
                            location: highlight.location,
                            quoteText: highlight.quoteText
                        )
                    }
                )
            }
        } catch {
            fatalError("Failed to prepare bulk highlight deletion: \(error)")
        }
    }

    static func deleteHighlights(using plan: BulkHighlightDeletionPlan) -> LibrarySnapshot {
        do {
            return try shared.write { database in
                let capturedHighlights = plan.highlights
                guard !capturedHighlights.isEmpty else {
                    return try makeLibrarySnapshot(database: database)
                }

                let deletedAt = iso8601Formatter.string(from: Date())
                let quoteIdentityKeys = capturedHighlights.map { highlight in
                    computeImportStableQuoteIdentity(
                        bookTitle: highlight.bookTitle,
                        author: highlight.author,
                        location: highlight.location,
                        quoteText: highlight.quoteText
                    )
                }
                try insertHighlightTombstones(
                    quoteIdentityKeys: quoteIdentityKeys,
                    deletedAt: deletedAt,
                    database: database
                )

                let capturedHighlightIDs = capturedHighlights.map(\.id.uuidString)
                try deleteRows(
                    from: "highlights",
                    idColumn: "id",
                    ids: capturedHighlightIDs,
                    batchRowLimit: deleteSelectionBatchRowLimit,
                    database: database
                )

                return try makeLibrarySnapshot(database: database)
            }
        } catch {
            fatalError("Failed to delete highlights: \(error)")
        }
    }

    static func makeBulkBookDeletionPlan(bookIDs: [UUID]) -> BulkBookDeletionPlan {
        do {
            return try shared.read { database in
                let capturedBookIDs = try fetchLiveBookIDs(matchingIDs: bookIDs, database: database)
                guard !capturedBookIDs.isEmpty else {
                    return BulkBookDeletionPlan(bookIDs: [], linkedHighlights: [])
                }

                let linkedHighlights = try fetchLiveLinkedHighlights(
                    linkedToBookIDs: capturedBookIDs,
                    database: database
                )
                return BulkBookDeletionPlan(
                    bookIDs: capturedBookIDs,
                    linkedHighlights: linkedHighlights
                )
            }
        } catch {
            fatalError("Failed to prepare bulk book deletion: \(error)")
        }
    }

    static func deleteBooks(using plan: BulkBookDeletionPlan) -> LibrarySnapshot {
        do {
            return try shared.write { database in
                let capturedBookIDs = uniqueUUIDStrings(from: plan.bookIDs)
                guard !capturedBookIDs.isEmpty else {
                    return try makeLibrarySnapshot(database: database)
                }

                let deletedAt = iso8601Formatter.string(from: Date())
                let quoteIdentityKeys = plan.linkedHighlights.map { linkedHighlight in
                    computeImportStableQuoteIdentity(
                        bookTitle: linkedHighlight.bookTitle,
                        author: linkedHighlight.author,
                        location: linkedHighlight.location,
                        quoteText: linkedHighlight.quoteText
                    )
                }
                try insertHighlightTombstones(
                    quoteIdentityKeys: quoteIdentityKeys,
                    deletedAt: deletedAt,
                    database: database
                )

                let capturedLinkedHighlightIDs = uniqueUUIDStrings(from: plan.linkedHighlightIDs)
                // Batched helper emits DELETE FROM highlights for the captured linked rows.
                try deleteRows(
                    from: "highlights",
                    idColumn: "id",
                    ids: capturedLinkedHighlightIDs,
                    batchRowLimit: deleteSelectionBatchRowLimit,
                    database: database
                )

                // Batched helper emits DELETE FROM books for the captured selection.
                try deleteRows(
                    from: "books",
                    idColumn: "id",
                    ids: capturedBookIDs,
                    batchRowLimit: deleteSelectionBatchRowLimit,
                    database: database
                )

                return try makeLibrarySnapshot(database: database)
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
                let persistedBookIDsByParsedID = try bulkUpsertBooksForImport(
                    books,
                    database: database
                )

                var missingBookMappingCount = 0
                var importHighlightRows: [ImportHighlightInsertRow] = []
                importHighlightRows.reserveCapacity(highlights.count)

                for highlight in highlights {
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
                    importHighlightRows.append(
                        ImportHighlightInsertRow(
                            highlight: persistedHighlight,
                            quoteIdentityKey: computeImportStableQuoteIdentity(
                                bookTitle: persistedHighlight.bookTitle,
                                author: persistedHighlight.author,
                                location: persistedHighlight.location,
                                quoteText: persistedHighlight.quoteText
                            ),
                            dedupeKey: computeDedupeKey(for: persistedHighlight)
                        )
                    )
                }

                let persistedHighlights = importHighlightRows.map(\.highlight)
                let existingTombstoneIdentityKeys = try fetchExistingImportTombstoneIdentityKeys(
                    for: persistedHighlights,
                    database: database
                )
                var knownDedupeKeys = try fetchExistingHighlightDedupeKeys(
                    for: persistedHighlights,
                    database: database
                )

                var survivingImportHighlightRows: [ImportHighlightInsertRow] = []
                survivingImportHighlightRows.reserveCapacity(importHighlightRows.count)

                for importHighlightRow in importHighlightRows {
                    guard existingTombstoneIdentityKeys.contains(importHighlightRow.quoteIdentityKey) == false else {
                        continue
                    }

                    guard knownDedupeKeys.insert(importHighlightRow.dedupeKey).inserted else {
                        continue
                    }

                    survivingImportHighlightRows.append(importHighlightRow)
                }

                let insertedHighlightCount = try bulkInsertHighlightsForImport(
                    survivingImportHighlightRows,
                    database: database
                )

                return ImportPersistenceResult(
                    newHighlightCount: insertedHighlightCount,
                    missingBookMappingCount: missingBookMappingCount,
                    librarySnapshot: try makeLibrarySnapshot(database: database)
                )
            }
        } catch {
            fatalError("Failed to persist import: \(error)")
        }
    }

    static func fetchAllBooks() -> [Book] {
        do {
            return try shared.read { database in
                try fetchAllBooks(database: database)
            }
        } catch {
            fatalError("Failed to fetch all books: \(error)")
        }
    }

    static func fetchAllHighlights(sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded) -> [Highlight] {
        let signpostState = quotesPerformanceSignposter.beginInterval(
            "QuotesDBFetch",
            "sortMode=\(sortMode.rawValue, privacy: .public)"
        )

        do {
            let highlights = try shared.read { database in
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                    SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled
                    FROM highlights
                    ORDER BY \(highlightsOrderClause(sortedBy: sortMode))
                    """
                )

                return rows.map(highlight(from:))
            }

            quotesPerformanceSignposter.endInterval(
                "QuotesDBFetch",
                signpostState,
                "rows=\(highlights.count)"
            )
            return highlights
        } catch {
            quotesPerformanceSignposter.endInterval(
                "QuotesDBFetch",
                signpostState,
                "failed=1"
            )
            fatalError("Failed to fetch all highlights: \(error)")
        }
    }

    static func fetchHighlightsPage(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters(),
        sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded,
        limit: Int,
        offset: Int
    ) -> [Highlight] {
        guard limit > 0, offset >= 0 else {
            return []
        }

        let signpostState = quotesPerformanceSignposter.beginInterval(
            "QuotesDBPageFetch",
            "sortMode=\(sortMode.rawValue, privacy: .public) limit=\(limit) offset=\(offset)"
        )

        do {
            let highlights = try shared.read { database in
                switch sortMode {
                case .mostRecentlyAdded:
                    return try fetchMostRecentHighlightsPage(
                        searchText: searchText,
                        filters: filters,
                        limit: limit,
                        offset: offset,
                        database: database
                    )
                case .alphabeticalByBook:
                    let query = quotesAlphabeticalPageQuery(
                        searchText: searchText,
                        filters: filters,
                        limit: limit,
                        offset: offset
                    )
                    let rows = try Row.fetchAll(
                        database,
                        sql: query.sql,
                        arguments: query.arguments
                    )
                    return rows.map(highlight(from:))
                }
            }

            quotesPerformanceSignposter.endInterval(
                "QuotesDBPageFetch",
                signpostState,
                "rows=\(highlights.count)"
            )
            return highlights
        } catch {
            quotesPerformanceSignposter.endInterval(
                "QuotesDBPageFetch",
                signpostState,
                "failed=1"
            )
            fatalError("Failed to fetch highlight page: \(error)")
        }
    }

    static func fetchHighlightPagePayload(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters(),
        sortedBy sortMode: QuotesListSortMode = .mostRecentlyAdded,
        limit: Int,
        offset: Int
    ) -> QuotesPagePayload {
        guard limit > 0, offset >= 0 else {
            return QuotesPagePayload(highlights: [], totalMatchingHighlightCount: 0)
        }

        let signpostState = quotesPerformanceSignposter.beginInterval(
            "QuotesDBPagePayloadFetch",
            "sortMode=\(sortMode.rawValue, privacy: .public) limit=\(limit) offset=\(offset)"
        )

        do {
            let payload = try shared.read { database in
                let totalMatchingHighlightCount = try fetchHighlightsCount(
                    searchText: searchText,
                    filters: filters,
                    database: database
                )
                let highlights: [Highlight]
                switch sortMode {
                case .mostRecentlyAdded:
                    highlights = try fetchMostRecentHighlightsPage(
                        searchText: searchText,
                        filters: filters,
                        limit: limit,
                        offset: offset,
                        database: database
                    )
                case .alphabeticalByBook:
                    let query = quotesAlphabeticalPageQuery(
                        searchText: searchText,
                        filters: filters,
                        limit: limit,
                        offset: offset
                    )
                    let rows = try Row.fetchAll(
                        database,
                        sql: query.sql,
                        arguments: query.arguments
                    )
                    highlights = rows.map(highlight(from:))
                }

                return QuotesPagePayload(
                    highlights: highlights,
                    totalMatchingHighlightCount: totalMatchingHighlightCount
                )
            }

            quotesPerformanceSignposter.endInterval(
                "QuotesDBPagePayloadFetch",
                signpostState,
                "rows=\(payload.highlights.count) total=\(payload.totalMatchingHighlightCount)"
            )
            return payload
        } catch {
            quotesPerformanceSignposter.endInterval(
                "QuotesDBPagePayloadFetch",
                signpostState,
                "failed=1"
            )
            fatalError("Failed to fetch highlight page payload: \(error)")
        }
    }

    static func fetchHighlightFilterOptions(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> QuotesFilterOptionsPayload {
        do {
            return try shared.read { database in
                let bookTitlesQuery = quotesFilterOptionsQuery(
                    field: .bookTitle,
                    searchText: searchText,
                    filters: filters
                )
                let authorsQuery = quotesFilterOptionsQuery(
                    field: .author,
                    searchText: searchText,
                    filters: filters
                )

                return QuotesFilterOptionsPayload(
                    availableBookTitles: try String.fetchAll(
                        database,
                        sql: bookTitlesQuery.sql,
                        arguments: bookTitlesQuery.arguments
                    ),
                    availableAuthors: try String.fetchAll(
                        database,
                        sql: authorsQuery.sql,
                        arguments: authorsQuery.arguments
                    )
                )
            }
        } catch {
            fatalError("Failed to fetch quote filter options: \(error)")
        }
    }

    static func fetchAvailableHighlightBookTitles(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> [String] {
        do {
            return try shared.read { database in
                let query = quotesFilterOptionsQuery(
                    field: .bookTitle,
                    searchText: searchText,
                    filters: filters
                )
                return try String.fetchAll(
                    database,
                    sql: query.sql,
                    arguments: query.arguments
                )
            }
        } catch {
            fatalError("Failed to fetch quote book title filters: \(error)")
        }
    }

    static func fetchAvailableHighlightAuthors(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> [String] {
        do {
            return try shared.read { database in
                let query = quotesFilterOptionsQuery(
                    field: .author,
                    searchText: searchText,
                    filters: filters
                )
                return try String.fetchAll(
                    database,
                    sql: query.sql,
                    arguments: query.arguments
                )
            }
        } catch {
            fatalError("Failed to fetch quote author filters: \(error)")
        }
    }

    static func countHighlights(
        searchText: String = "",
        filters: QuotesListFilters = QuotesListFilters()
    ) -> Int {
        do {
            return try shared.read { database in
                try fetchHighlightsCount(
                    searchText: searchText,
                    filters: filters,
                    database: database
                )
            }
        } catch {
            fatalError("Failed to count quote results: \(error)")
        }
    }

    static func totalHighlightCount() -> Int {
        do {
            return try shared.read { database in
                try totalHighlightCount(database: database)
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
        let quoteIdentityKey = computeImportStableQuoteIdentity(
            bookTitle: bookTitle,
            author: author,
            location: location,
            quoteText: quoteText
        )

        do {
            return try shared.read { database in
                try hasHighlightTombstone(
                    quoteIdentityKey: quoteIdentityKey,
                    database: database
                )
            }
        } catch {
            fatalError("Failed to check highlight tombstone: \(error)")
        }
    }

    private static func computeDedupeKey(for highlight: Highlight) -> String {
        DedupeKeyBuilder.makeKey(
            bookId: highlight.bookId,
            bookTitle: highlight.bookTitle,
            author: highlight.author,
            location: highlight.location,
            quoteText: highlight.quoteText
        )
    }

    private static func computeImportStableQuoteIdentity(
        bookTitle: String,
        author: String,
        location: String?,
        quoteText: String
    ) -> String {
        ImportStableQuoteIdentityKeyBuilder.makeKey(
            bookTitle: bookTitle,
            author: author,
            location: location,
            quoteText: quoteText
        )
    }

    private static func iso8601String(from date: Date?) -> String? {
        guard let date else {
            return nil
        }
        return iso8601Formatter.string(from: date)
    }

    private static func highlightsOrderClause(sortedBy sortMode: QuotesListSortMode) -> String {
        switch sortMode {
        case .mostRecentlyAdded:
            return """
            CASE WHEN dateAdded IS NULL THEN 1 ELSE 0 END ASC,
            dateAdded DESC,
            \(alphabeticalHighlightsOrderClause)
            """
        case .alphabeticalByBook:
            return alphabeticalHighlightsOrderClause
        }
    }

    private enum QuotesFilterOptionField {
        case bookTitle
        case author
    }

    private static func quotesAlphabeticalPageQuery(
        searchText: String,
        filters: QuotesListFilters,
        limit: Int,
        offset: Int
    ) -> (sql: String, arguments: StatementArguments) {
        var query = quotesListWhereClause(
            searchText: searchText,
            filters: filters
        )
        query.sql = """
        SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled
        FROM highlights\(query.sql)

        ORDER BY \(alphabeticalHighlightsOrderClause)
        LIMIT ? OFFSET ?
        """
        query.arguments += [limit, offset]
        return query
    }

    private static func fetchMostRecentHighlightsPage(
        searchText: String,
        filters: QuotesListFilters,
        limit: Int,
        offset: Int,
        database: Database
    ) throws -> [Highlight] {
        let nonNullDateCount = try fetchHighlightsCount(
            searchText: searchText,
            filters: filters,
            additionalConditions: ["dateAdded IS NOT NULL"],
            database: database
        )

        if offset >= nonNullDateCount {
            return try fetchMostRecentHighlightsSegment(
                searchText: searchText,
                filters: filters,
                dateAddedCondition: "dateAdded IS NULL",
                orderClause: alphabeticalHighlightsOrderClause,
                limit: limit,
                offset: offset - nonNullDateCount,
                database: database
            )
        }

        var highlights = try fetchMostRecentHighlightsSegment(
            searchText: searchText,
            filters: filters,
            dateAddedCondition: "dateAdded IS NOT NULL",
            orderClause: """
            dateAdded DESC,
            \(alphabeticalHighlightsOrderClause)
            """,
            limit: limit,
            offset: offset,
            database: database
        )

        if highlights.count < limit {
            let remainingLimit = limit - highlights.count
            let nullDateHighlights = try fetchMostRecentHighlightsSegment(
                searchText: searchText,
                filters: filters,
                dateAddedCondition: "dateAdded IS NULL",
                orderClause: alphabeticalHighlightsOrderClause,
                limit: remainingLimit,
                offset: 0,
                database: database
            )
            highlights.append(contentsOf: nullDateHighlights)
        }

        return highlights
    }

    private static func fetchHighlightsCount(
        searchText: String,
        filters: QuotesListFilters,
        additionalConditions: [String] = [],
        database: Database
    ) throws -> Int {
        let query = quotesListWhereClause(
            searchText: searchText,
            filters: filters,
            additionalConditions: additionalConditions
        )
        return try Int.fetchOne(
            database,
            sql: """
            SELECT COUNT(*)
            FROM highlights\(query.sql)
            """,
            arguments: query.arguments
        ) ?? 0
    }

    private static func fetchMostRecentHighlightsSegment(
        searchText: String,
        filters: QuotesListFilters,
        dateAddedCondition: String,
        orderClause: String,
        limit: Int,
        offset: Int,
        database: Database
    ) throws -> [Highlight] {
        var query = quotesListWhereClause(
            searchText: searchText,
            filters: filters,
            additionalConditions: [dateAddedCondition]
        )
        query.sql = """
        SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled
        FROM highlights\(query.sql)

        ORDER BY \(orderClause)
        LIMIT ? OFFSET ?
        """
        query.arguments += [limit, offset]

        let rows = try Row.fetchAll(
            database,
            sql: query.sql,
            arguments: query.arguments
        )
        return rows.map(highlight(from:))
    }

    private static func quotesFilterOptionsQuery(
        field: QuotesFilterOptionField,
        searchText: String,
        filters: QuotesListFilters
    ) -> (sql: String, arguments: StatementArguments) {
        let fieldExpression: String
        let excludedField: QuotesFilterOptionField

        switch field {
        case .bookTitle:
            fieldExpression = normalizedBookTitleExpressionSQL
            excludedField = .bookTitle
        case .author:
            fieldExpression = normalizedAuthorExpressionSQL
            excludedField = .author
        }

        let query = quotesListWhereClause(
            searchText: searchText,
            filters: filters,
            excluding: excludedField
        )
        return (
            """
        SELECT DISTINCT \(fieldExpression) AS value
        FROM highlights\(query.sql)
        ORDER BY value COLLATE NOCASE ASC
        """,
            query.arguments
        )
    }

    private static func quotesListWhereClause(
        searchText: String,
        filters: QuotesListFilters,
        excluding excludedField: QuotesFilterOptionField? = nil,
        additionalConditions: [String] = []
    ) -> (sql: String, arguments: StatementArguments) {
        var conditions = additionalConditions
        var arguments: StatementArguments = []

        if excludedField != .bookTitle,
           let selectedBookTitle = normalizedFilterSelectionValue(filters.selectedBookTitle) {
            conditions.append("\(normalizedBookTitleExpressionSQL) = ?")
            arguments += [selectedBookTitle]
        }

        if excludedField != .author,
           let selectedAuthor = normalizedFilterSelectionValue(filters.selectedAuthor) {
            conditions.append("\(normalizedAuthorExpressionSQL) = ?")
            arguments += [selectedAuthor]
        }

        switch filters.source {
        case .allQuotes:
            break
        case .manualOnly:
            conditions.append("bookId IS NULL")
        }

        switch filters.bookStatus {
        case .allBooks:
            break
        case .enabledBooksOnly:
            conditions.append("bookId IS NOT NULL")
            conditions.append("bookId IN (SELECT id FROM books WHERE isEnabled = 1)")
        case .disabledBooksOnly:
            conditions.append("bookId IS NOT NULL")
            conditions.append("bookId IN (SELECT id FROM books WHERE isEnabled = 0)")
        }

        if let searchPattern = normalizedSearchPattern(for: searchText) {
            conditions.append(
                """
                (
                    quoteText LIKE ? COLLATE NOCASE
                    OR bookTitle LIKE ? COLLATE NOCASE
                    OR author LIKE ? COLLATE NOCASE
                )
                """
            )
            arguments += [searchPattern, searchPattern, searchPattern]
        }

        let whereClause: String
        if conditions.isEmpty {
            whereClause = ""
        } else {
            whereClause = """

            WHERE \(conditions.joined(separator: "\n  AND "))
            """
        }

        return (whereClause, arguments)
    }

    private static func normalizedFilterSelectionValue(_ rawValue: String?) -> String? {
        guard let rawValue else {
            return nil
        }

        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    private static func normalizedSearchPattern(for rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }
        return "%\(trimmedValue)%"
    }

    private static let alphabeticalHighlightsOrderClause = """
    bookTitle COLLATE NOCASE ASC,
    author COLLATE NOCASE ASC,
    quoteText COLLATE NOCASE ASC,
    id ASC
    """

    private static func insertHighlightTombstones(
        quoteIdentityKeys: [String],
        deletedAt: String,
        database: Database
    ) throws {
        let uniqueQuoteIdentityKeys = uniqueStringsPreservingOrder(from: quoteIdentityKeys)
        guard !uniqueQuoteIdentityKeys.isEmpty else {
            return
        }

        var batchStartIndex = 0
        while batchStartIndex < uniqueQuoteIdentityKeys.count {
            let batchEndIndex = min(batchStartIndex + tombstoneInsertBatchRowLimit, uniqueQuoteIdentityKeys.count)
            let tombstoneBatch = Array(uniqueQuoteIdentityKeys[batchStartIndex..<batchEndIndex])
            let sqlValueTuples = Array(repeating: "(?, ?)", count: tombstoneBatch.count).joined(separator: ", ")

            try database.execute(
                sql: """
                INSERT OR IGNORE INTO highlight_tombstones (quoteIdentityKey, deletedAt)
                VALUES \(sqlValueTuples)
                """,
                arguments: StatementArguments(tombstoneBatch.flatMap { [$0, deletedAt] })
            )

            batchStartIndex = batchEndIndex
        }
    }

    private static func bulkUpsertBooksForImport(
        _ books: [Book],
        database: Database
    ) throws -> [UUID: UUID] {
        guard !books.isEmpty else {
            return [:]
        }

        var persistedBookIDsByParsedID: [UUID: UUID] = [:]
        persistedBookIDsByParsedID.reserveCapacity(books.count)

        var batchStartIndex = 0
        while batchStartIndex < books.count {
            let batchEndIndex = min(batchStartIndex + importBookUpsertBatchRowLimit, books.count)
            let bookBatch = Array(books[batchStartIndex..<batchEndIndex])
            let sqlValueTuples = Array(repeating: "(?, ?, ?, ?)", count: bookBatch.count).joined(separator: ", ")

            var insertArguments: [(any DatabaseValueConvertible)?] = []
            insertArguments.reserveCapacity(bookBatch.count * 4)

            for book in bookBatch {
                insertArguments.append(book.id.uuidString)
                insertArguments.append(book.title)
                insertArguments.append(book.author)
                insertArguments.append(book.isEnabled ? 1 : 0)
            }

            try database.execute(
                sql: """
                INSERT OR IGNORE INTO books (id, title, author, isEnabled)
                VALUES \(sqlValueTuples)
                """,
                arguments: StatementArguments(insertArguments)
            )

            let persistedBatchBookIDs = try fetchPersistedImportBookIDs(
                for: bookBatch,
                database: database
            )
            persistedBookIDsByParsedID.merge(persistedBatchBookIDs) { _, rhs in rhs }

            guard persistedBatchBookIDs.count == bookBatch.count else {
                fatalError("Failed to resolve all imported books after bulk upsert")
            }

            batchStartIndex = batchEndIndex
        }

        return persistedBookIDsByParsedID
    }

    private static func fetchPersistedImportBookIDs(
        for books: [Book],
        database: Database
    ) throws -> [UUID: UUID] {
        guard !books.isEmpty else {
            return [:]
        }

        let sqlValueTuples = Array(repeating: "(?, ?, ?)", count: books.count).joined(separator: ", ")
        var arguments: [(any DatabaseValueConvertible)?] = []
        arguments.reserveCapacity(books.count * 3)

        for book in books {
            arguments.append(book.id.uuidString)
            arguments.append(book.title)
            arguments.append(book.author)
        }

        let rows = try Row.fetchAll(
            database,
            sql: """
            WITH import_books(parsedID, title, author) AS (
                VALUES \(sqlValueTuples)
            )
            SELECT import_books.parsedID, books.id AS storedID
            FROM import_books
            JOIN books
                ON books.title = import_books.title
               AND books.author = import_books.author
            """,
            arguments: StatementArguments(arguments)
        )

        var persistedBookIDsByParsedID: [UUID: UUID] = [:]
        persistedBookIDsByParsedID.reserveCapacity(books.count)

        for row in rows {
            guard
                let parsedBookIDValue: String = row["parsedID"],
                let parsedBookID = UUID(uuidString: parsedBookIDValue),
                let storedBookIDValue: String = row["storedID"],
                let storedBookID = UUID(uuidString: storedBookIDValue)
            else {
                fatalError("Invalid book id returned while resolving imported books")
            }

            persistedBookIDsByParsedID[parsedBookID] = storedBookID
        }

        return persistedBookIDsByParsedID
    }

    private static func upsertBook(_ book: Book, database: Database) throws -> UUID {
        try database.execute(
            sql: """
            INSERT OR IGNORE INTO books (id, title, author, isEnabled)
            VALUES (?, ?, ?, ?)
            """,
            arguments: [book.id.uuidString, book.title, book.author, book.isEnabled ? 1 : 0]
        )

        guard let storedBookID = try String.fetchOne(
            database,
            sql: """
            SELECT id
            FROM books
            WHERE title = ? AND author = ?
            LIMIT 1
            """,
            arguments: [book.title, book.author]
        ) else {
            fatalError("Failed to find book row after upsert for title '\(book.title)' and author '\(book.author)'")
        }

        guard let uuid = UUID(uuidString: storedBookID) else {
            fatalError("Invalid UUID stored for book id '\(storedBookID)'")
        }

        return uuid
    }

    private static func insertHighlightIfNew(
        _ highlight: Highlight,
        database: Database
    ) throws -> Bool {
        let dedupeKey = computeDedupeKey(for: highlight)
        guard try hasHighlight(dedupeKey: dedupeKey, database: database) == false else {
            return false
        }

        try insertHighlight(highlight, dedupeKey: dedupeKey, database: database)
        return true
    }

    private static func insertHighlight(
        _ highlight: Highlight,
        dedupeKey: String,
        database: Database
    ) throws {
        try database.execute(
            sql: """
            INSERT INTO highlights (
                id,
                bookId,
                quoteText,
                bookTitle,
                author,
                location,
                dateAdded,
                lastShownAt,
                isEnabled,
                dedupeKey
            )
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            arguments: [
                highlight.id.uuidString,
                highlight.bookId?.uuidString,
                highlight.quoteText,
                highlight.bookTitle,
                highlight.author,
                highlight.location,
                iso8601String(from: highlight.dateAdded),
                iso8601String(from: highlight.lastShownAt),
                highlight.isEnabled ? 1 : 0,
                dedupeKey
            ]
        )
    }

    private static func bulkInsertHighlightsForImport(
        _ importHighlightRows: [ImportHighlightInsertRow],
        database: Database
    ) throws -> Int {
        guard !importHighlightRows.isEmpty else {
            return 0
        }

        var insertedHighlightCount = 0
        var batchStartIndex = 0

        while batchStartIndex < importHighlightRows.count {
            let batchEndIndex = min(batchStartIndex + importHighlightInsertBatchRowLimit, importHighlightRows.count)
            let highlightBatch = Array(importHighlightRows[batchStartIndex..<batchEndIndex])
            let sqlValueTuples = Array(repeating: "(?, ?, ?, ?, ?, ?, ?, ?, ?, ?)", count: highlightBatch.count)
                .joined(separator: ", ")
            var arguments: [(any DatabaseValueConvertible)?] = []
            arguments.reserveCapacity(highlightBatch.count * 10)

            for importHighlightRow in highlightBatch {
                let highlight = importHighlightRow.highlight
                arguments.append(highlight.id.uuidString)
                arguments.append(highlight.bookId?.uuidString)
                arguments.append(highlight.quoteText)
                arguments.append(highlight.bookTitle)
                arguments.append(highlight.author)
                arguments.append(highlight.location)
                arguments.append(iso8601String(from: highlight.dateAdded))
                arguments.append(iso8601String(from: highlight.lastShownAt))
                arguments.append(highlight.isEnabled ? 1 : 0)
                arguments.append(importHighlightRow.dedupeKey)
            }

            try database.execute(
                sql: """
                INSERT INTO highlights (
                    id,
                    bookId,
                    quoteText,
                    bookTitle,
                    author,
                    location,
                    dateAdded,
                    lastShownAt,
                    isEnabled,
                    dedupeKey
                )
                VALUES \(sqlValueTuples)
                """,
                arguments: StatementArguments(arguments)
            )

            insertedHighlightCount += highlightBatch.count
            batchStartIndex = batchEndIndex
        }

        return insertedHighlightCount
    }

    private static func fetchAllBooks(database: Database) throws -> [Book] {
        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT
                books.id,
                books.title,
                books.author,
                books.isEnabled,
                COUNT(highlights.id) AS highlightCount
            FROM books
            LEFT JOIN highlights ON highlights.bookId = books.id
            GROUP BY books.id, books.title, books.author, books.isEnabled
            ORDER BY books.title COLLATE NOCASE ASC
            """
        )

        return rows.map { row in
            guard
                let idValue: String = row["id"],
                let id = UUID(uuidString: idValue)
            else {
                fatalError("Invalid book id in database row")
            }

            let isEnabledValue: Int = row["isEnabled"]
            let highlightCountValue: Int = row["highlightCount"]

            return Book(
                id: id,
                title: row["title"],
                author: row["author"],
                isEnabled: isEnabledValue != 0,
                highlightCount: highlightCountValue
            )
        }
    }

    private static func totalHighlightCount(database: Database) throws -> Int {
        try Int.fetchOne(
            database,
            sql: """
            SELECT COUNT(*)
            FROM highlights
            """
        ) ?? 0
    }

    private static func makeLibrarySnapshot(database: Database) throws -> LibrarySnapshot {
        LibrarySnapshot(
            totalHighlightCount: try totalHighlightCount(database: database),
            books: try fetchAllBooks(database: database)
        )
    }

    private static func hasHighlightTombstone(
        highlight: Highlight,
        database: Database
    ) throws -> Bool {
        let quoteIdentityKey = computeImportStableQuoteIdentity(
            bookTitle: highlight.bookTitle,
            author: highlight.author,
            location: highlight.location,
            quoteText: highlight.quoteText
        )
        return try hasHighlightTombstone(
            quoteIdentityKey: quoteIdentityKey,
            database: database
        )
    }

    private static func hasHighlightTombstone(
        quoteIdentityKey: String,
        database: Database
    ) throws -> Bool {
        try Int.fetchOne(
            database,
            sql: """
            SELECT 1
            FROM highlight_tombstones
            WHERE quoteIdentityKey = ?
            LIMIT 1
            """,
            arguments: [quoteIdentityKey]
        ) != nil
    }

    private static func fetchExistingImportTombstoneIdentityKeys(
        for highlights: [Highlight],
        database: Database
    ) throws -> Set<String> {
        let quoteIdentityKeys = uniqueStringsPreservingOrder(from: highlights.map { highlight in
            computeImportStableQuoteIdentity(
                bookTitle: highlight.bookTitle,
                author: highlight.author,
                location: highlight.location,
                quoteText: highlight.quoteText
            )
        })
        guard !quoteIdentityKeys.isEmpty else {
            return []
        }

        var existingQuoteIdentityKeys = Set<String>()
        var batchStartIndex = 0

        while batchStartIndex < quoteIdentityKeys.count {
            let batchEndIndex = min(batchStartIndex + importPreflightBatchRowLimit, quoteIdentityKeys.count)
            let quoteIdentityKeyBatch = Array(quoteIdentityKeys[batchStartIndex..<batchEndIndex])

            let existingBatchKeys = try String.fetchAll(
                database,
                sql: """
                SELECT quoteIdentityKey
                FROM highlight_tombstones
                WHERE quoteIdentityKey IN (\(sqlPlaceholders(count: quoteIdentityKeyBatch.count)))
                """,
                arguments: StatementArguments(quoteIdentityKeyBatch)
            )
            existingQuoteIdentityKeys.formUnion(existingBatchKeys)
            batchStartIndex = batchEndIndex
        }

        return existingQuoteIdentityKeys
    }

    private static func fetchExistingHighlightDedupeKeys(
        for highlights: [Highlight],
        database: Database
    ) throws -> Set<String> {
        let dedupeKeys = uniqueStringsPreservingOrder(from: highlights.map { highlight in
            computeDedupeKey(for: highlight)
        })
        guard !dedupeKeys.isEmpty else {
            return []
        }

        var existingDedupeKeys = Set<String>()
        var batchStartIndex = 0

        while batchStartIndex < dedupeKeys.count {
            let batchEndIndex = min(batchStartIndex + importPreflightBatchRowLimit, dedupeKeys.count)
            let dedupeKeyBatch = Array(dedupeKeys[batchStartIndex..<batchEndIndex])

            let existingBatchKeys = try String.fetchAll(
                database,
                sql: """
                SELECT dedupeKey
                FROM highlights
                WHERE dedupeKey IN (\(sqlPlaceholders(count: dedupeKeyBatch.count)))
                """,
                arguments: StatementArguments(dedupeKeyBatch)
            )
            existingDedupeKeys.formUnion(existingBatchKeys)
            batchStartIndex = batchEndIndex
        }

        return existingDedupeKeys
    }

    private static func hasHighlight(
        dedupeKey: String,
        database: Database
    ) throws -> Bool {
        try Int.fetchOne(
            database,
            sql: """
            SELECT 1
            FROM highlights
            WHERE dedupeKey = ?
            LIMIT 1
            """,
            arguments: [dedupeKey]
        ) != nil
    }

    private static func fetchLiveHighlights(matchingIDs ids: [UUID], database: Database) throws -> [Highlight] {
        let uniqueHighlightIDs = uniqueUUIDStrings(from: ids)
        guard !uniqueHighlightIDs.isEmpty else {
            return []
        }

        let capturedHighlightsByID = try fetchHighlightsByID(
            uniqueHighlightIDs,
            batchRowLimit: deleteSelectionBatchRowLimit,
            database: database
        )

        return uniqueHighlightIDs.compactMap { capturedHighlightsByID[$0] }
    }

    private static func fetchLiveBookIDs(matchingIDs ids: [UUID], database: Database) throws -> [UUID] {
        let uniqueBookIDs = uniqueUUIDStrings(from: ids)
        guard !uniqueBookIDs.isEmpty else {
            return []
        }

        let storedBookIDSet = try fetchExistingBookIDSet(
            uniqueBookIDs,
            batchRowLimit: deleteSelectionBatchRowLimit,
            database: database
        )

        return uniqueBookIDs.compactMap { bookIDString in
            guard storedBookIDSet.contains(bookIDString) else {
                return nil
            }

            guard let bookID = UUID(uuidString: bookIDString) else {
                fatalError("Invalid book id in database row")
            }
            return bookID
        }
    }

    private static func fetchLiveLinkedHighlights(
        linkedToBookIDs bookIDs: [UUID],
        database: Database
    ) throws -> [BulkBookDeletionLinkedHighlight] {
        let uniqueBookIDs = uniqueUUIDStrings(from: bookIDs)
        guard !uniqueBookIDs.isEmpty else {
            return []
        }

        var linkedHighlights: [BulkBookDeletionLinkedHighlight] = []

        try forEachStringBatch(
            uniqueBookIDs,
            batchRowLimit: deleteSelectionBatchRowLimit
        ) { bookIDBatch in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT id, bookId, bookTitle, author, location, quoteText
                FROM highlights
                WHERE bookId IN (\(sqlPlaceholders(count: bookIDBatch.count)))
                """,
                arguments: StatementArguments(bookIDBatch)
            )

            linkedHighlights.append(contentsOf: rows.map(linkedHighlight(from:)))
        }

        linkedHighlights.sort(by: bulkBookDeletionLinkedHighlightSort)
        return linkedHighlights
    }

    private static func fetchHighlightsByID(
        _ ids: [String],
        batchRowLimit: Int,
        database: Database
    ) throws -> [String: Highlight] {
        var capturedHighlightsByID: [String: Highlight] = [:]
        capturedHighlightsByID.reserveCapacity(ids.count)

        try forEachStringBatch(ids, batchRowLimit: batchRowLimit) { highlightIDBatch in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled
                FROM highlights
                WHERE id IN (\(sqlPlaceholders(count: highlightIDBatch.count)))
                """,
                arguments: StatementArguments(highlightIDBatch)
            )

            for row in rows {
                let highlight = highlight(from: row)
                capturedHighlightsByID[highlight.id.uuidString] = highlight
            }
        }

        return capturedHighlightsByID
    }

    private static func fetchExistingBookIDSet(
        _ ids: [String],
        batchRowLimit: Int,
        database: Database
    ) throws -> Set<String> {
        var storedBookIDSet = Set<String>()

        try forEachStringBatch(ids, batchRowLimit: batchRowLimit) { bookIDBatch in
            let storedBookIDRows = try Row.fetchAll(
                database,
                sql: """
                SELECT id
                FROM books
                WHERE id IN (\(sqlPlaceholders(count: bookIDBatch.count)))
                """,
                arguments: StatementArguments(bookIDBatch)
            )

            storedBookIDSet.formUnion(storedBookIDRows.compactMap { row in
                row["id"] as String?
            })
        }

        return storedBookIDSet
    }

    private static func deleteRows(
        from tableName: String,
        idColumn: String,
        ids: [String],
        batchRowLimit: Int,
        database: Database
    ) throws {
        guard !ids.isEmpty else {
            return
        }

        try forEachStringBatch(ids, batchRowLimit: batchRowLimit) { idBatch in
            try database.execute(
                sql: """
                DELETE FROM \(tableName)
                WHERE \(idColumn) IN (\(sqlPlaceholders(count: idBatch.count)))
                """,
                arguments: StatementArguments(idBatch)
            )
        }
    }

    private static func forEachStringBatch(
        _ values: [String],
        batchRowLimit: Int,
        body: ([String]) throws -> Void
    ) throws {
        guard !values.isEmpty else {
            return
        }

        var batchStartIndex = 0
        while batchStartIndex < values.count {
            let batchEndIndex = min(batchStartIndex + batchRowLimit, values.count)
            try body(Array(values[batchStartIndex..<batchEndIndex]))
            batchStartIndex = batchEndIndex
        }
    }

    private static func linkedHighlight(from row: Row) -> BulkBookDeletionLinkedHighlight {
        guard
            let idValue: String = row["id"],
            let id = UUID(uuidString: idValue)
        else {
            fatalError("Invalid highlight id in database row")
        }

        let bookIDValue: String? = row["bookId"]
        let bookID = bookIDValue.flatMap { UUID(uuidString: $0) }

        if bookIDValue != nil && bookID == nil {
            fatalError("Invalid linked highlight bookId in database row")
        }

        return BulkBookDeletionLinkedHighlight(
            id: id,
            bookID: bookID,
            bookTitle: row["bookTitle"],
            author: row["author"],
            location: row["location"],
            quoteText: row["quoteText"]
        )
    }

    private static func bulkBookDeletionLinkedHighlightSort(
        _ lhs: BulkBookDeletionLinkedHighlight,
        _ rhs: BulkBookDeletionLinkedHighlight
    ) -> Bool {
        let bookTitleComparison = lhs.bookTitle.localizedCaseInsensitiveCompare(rhs.bookTitle)
        if bookTitleComparison != .orderedSame {
            return bookTitleComparison == .orderedAscending
        }

        let authorComparison = lhs.author.localizedCaseInsensitiveCompare(rhs.author)
        if authorComparison != .orderedSame {
            return authorComparison == .orderedAscending
        }

        switch (lhs.location, rhs.location) {
        case let (lhsLocation?, rhsLocation?):
            let locationComparison = lhsLocation.localizedCaseInsensitiveCompare(rhsLocation)
            if locationComparison != .orderedSame {
                return locationComparison == .orderedAscending
            }
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        case (nil, nil):
            break
        }

        let quoteTextComparison = lhs.quoteText.localizedCaseInsensitiveCompare(rhs.quoteText)
        if quoteTextComparison != .orderedSame {
            return quoteTextComparison == .orderedAscending
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func uniqueUUIDStrings(from ids: [UUID]) -> [String] {
        var seen = Set<UUID>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else {
                return nil
            }
            return id.uuidString
        }
    }

    private static func uniqueStringsPreservingOrder(from values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }

    private static func sqlPlaceholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    private static func highlight(from row: Row) -> Highlight {
        guard
            let idValue: String = row["id"],
            let id = UUID(uuidString: idValue)
        else {
            fatalError("Invalid highlight id in database row")
        }

        let bookIDValue: String? = row["bookId"]
        let bookID = bookIDValue.flatMap { UUID(uuidString: $0) }

        if bookIDValue != nil && bookID == nil {
            fatalError("Invalid highlight bookId in database row")
        }

        let dateAddedValue: String? = row["dateAdded"]
        let lastShownAtValue: String? = row["lastShownAt"]
        let isEnabledValue: Int = row["isEnabled"]

        return Highlight(
            id: id,
            bookId: bookID,
            quoteText: row["quoteText"],
            bookTitle: row["bookTitle"],
            author: row["author"],
            location: row["location"],
            dateAdded: dateAddedValue.flatMap { iso8601Formatter.date(from: $0) },
            lastShownAt: lastShownAtValue.flatMap { iso8601Formatter.date(from: $0) },
            isEnabled: isEnabledValue != 0
        )
    }
}
