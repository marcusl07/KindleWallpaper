import Foundation
import GRDB
import OSLog

enum DatabaseManager {
    private static let tombstoneInsertBatchRowLimit = 400
    private static let quotesPerformanceSignposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.marcuslo.KindleWall",
        category: "QuotesPerformance"
    )

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

    static func updateHighlight(_ highlight: Highlight) {
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
        do {
            return try shared.write { database in
                let capturedLiveHighlights = try fetchLiveHighlights(matchingIDs: ids, database: database)
                guard !capturedLiveHighlights.isEmpty else {
                    return try makeLibrarySnapshot(database: database)
                }

                let deletedAt = iso8601Formatter.string(from: Date())
                let quoteIdentityKeys = capturedLiveHighlights.map { highlight in
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

                let capturedHighlightIDs = capturedLiveHighlights.map(\.id.uuidString)
                try database.execute(
                    sql: """
                    DELETE FROM highlights
                    WHERE id IN (\(sqlPlaceholders(count: capturedHighlightIDs.count)))
                    """,
                    arguments: StatementArguments(capturedHighlightIDs)
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
                if !capturedLinkedHighlightIDs.isEmpty {
                    try database.execute(
                        sql: """
                        DELETE FROM highlights
                        WHERE id IN (\(sqlPlaceholders(count: capturedLinkedHighlightIDs.count)))
                        """,
                        arguments: StatementArguments(capturedLinkedHighlightIDs)
                    )
                }

                try database.execute(
                    sql: """
                    DELETE FROM books
                    WHERE id IN (\(sqlPlaceholders(count: capturedBookIDs.count)))
                    """,
                    arguments: StatementArguments(capturedBookIDs)
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
                var persistedBookIDsByParsedID: [UUID: UUID] = [:]
                persistedBookIDsByParsedID.reserveCapacity(books.count)

                for book in books {
                    let persistedBookID = try upsertBook(book, database: database)
                    persistedBookIDsByParsedID[book.id] = persistedBookID
                }

                var missingBookMappingCount = 0
                var insertedHighlightCount = 0

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

                    guard try hasHighlightTombstone(highlight: persistedHighlight, database: database) == false else {
                        continue
                    }

                    if try insertHighlightIfNew(persistedHighlight, database: database) {
                        insertedHighlightCount += 1
                    }
                }

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
        let alreadyExists = try Int.fetchOne(
            database,
            sql: """
            SELECT 1
            FROM highlights
            WHERE dedupeKey = ?
            LIMIT 1
            """,
            arguments: [dedupeKey]
        ) != nil

        guard !alreadyExists else {
            return false
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

        return true
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

    private static func fetchLiveHighlights(matchingIDs ids: [UUID], database: Database) throws -> [Highlight] {
        let uniqueHighlightIDs = uniqueUUIDStrings(from: ids)
        guard !uniqueHighlightIDs.isEmpty else {
            return []
        }

        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled
            FROM highlights
            WHERE id IN (\(sqlPlaceholders(count: uniqueHighlightIDs.count)))
            """,
            arguments: StatementArguments(uniqueHighlightIDs)
        )

        return rows.map(highlight(from:))
    }

    private static func fetchLiveBookIDs(matchingIDs ids: [UUID], database: Database) throws -> [UUID] {
        let uniqueBookIDs = uniqueUUIDStrings(from: ids)
        guard !uniqueBookIDs.isEmpty else {
            return []
        }

        let storedBookIDRows = try Row.fetchAll(
            database,
            sql: """
            SELECT id
            FROM books
            WHERE id IN (\(sqlPlaceholders(count: uniqueBookIDs.count)))
            """,
            arguments: StatementArguments(uniqueBookIDs)
        )

        let storedBookIDSet = Set(storedBookIDRows.compactMap { row in
            row["id"] as String?
        })

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

        let rows = try Row.fetchAll(
            database,
            sql: """
            SELECT id, bookTitle, author, location, quoteText
            FROM highlights
            WHERE bookId IN (\(sqlPlaceholders(count: uniqueBookIDs.count)))
            ORDER BY
                bookTitle COLLATE NOCASE ASC,
                author COLLATE NOCASE ASC,
                CASE WHEN location IS NULL THEN 1 ELSE 0 END ASC,
                location COLLATE NOCASE ASC,
                quoteText COLLATE NOCASE ASC,
                id ASC
            """,
            arguments: StatementArguments(uniqueBookIDs)
        )

        return rows.map { row in
            guard
                let idValue: String = row["id"],
                let id = UUID(uuidString: idValue)
            else {
                fatalError("Invalid highlight id in database row")
            }

            return BulkBookDeletionLinkedHighlight(
                id: id,
                bookTitle: row["bookTitle"],
                author: row["author"],
                location: row["location"],
                quoteText: row["quoteText"]
            )
        }
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
