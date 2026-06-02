import Foundation
import GRDB

enum LibraryRepository {
    static let tombstoneInsertBatchRowLimit = 400
    static let deleteSelectionBatchRowLimit = 400

    private static let activeHighlightsPredicateSQL = """
    (bookId IS NULL OR bookId IN (SELECT id FROM books WHERE isEnabled = 1))
      AND isEnabled = 1
    """

    static func upsertBook(_ book: Book, database: Database) throws -> UUID {
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

    static func insertHighlightIfNew(_ highlight: Highlight, database: Database) throws -> Bool {
        let dedupeKey = QuoteIdentity.dedupeKey(for: highlight)
        guard try hasHighlight(dedupeKey: dedupeKey, database: database) == false else {
            return false
        }

        try insertHighlight(highlight, dedupeKey: dedupeKey, database: database)
        return true
    }

    static func insertHighlight(_ highlight: Highlight, dedupeKey: String, database: Database) throws {
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
                DatabaseRecordMapper.iso8601String(from: highlight.dateAdded),
                DatabaseRecordMapper.iso8601String(from: highlight.lastShownAt),
                highlight.isEnabled ? 1 : 0,
                dedupeKey
            ]
        )
    }

    static func setBookEnabled(id: UUID, enabled: Bool, database: Database) throws {
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

    static func setAllBooksEnabled(enabled: Bool, database: Database) throws {
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

    static func setHighlightEnabled(id: UUID, enabled: Bool, database: Database) throws {
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

    static func updateHighlight(_ highlight: Highlight, database: Database) throws {
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
                QuoteIdentity.dedupeKey(for: highlight),
                highlight.id.uuidString
            ]
        )
    }

    static func pickNextHighlight(database: Database) throws -> Highlight? {
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

        return DatabaseRecordMapper.highlight(from: row)
    }

    static func markHighlightShown(id: UUID, database: Database) throws {
        try database.execute(
            sql: """
            UPDATE highlights
            SET lastShownAt = ?
            WHERE id = ?
            """,
            arguments: [DatabaseRecordMapper.iso8601Formatter.string(from: Date()), id.uuidString]
        )
    }

    static func makeBulkHighlightDeletionPlan(
        highlightIDs: [UUID],
        database: Database
    ) throws -> BulkHighlightDeletionPlan {
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

    static func deleteHighlights(using plan: BulkHighlightDeletionPlan, database: Database) throws -> LibrarySnapshot {
        let capturedHighlights = plan.highlights
        guard !capturedHighlights.isEmpty else {
            return try makeLibrarySnapshot(database: database)
        }

        let deletedAt = DatabaseRecordMapper.iso8601Formatter.string(from: Date())
        let quoteIdentityKeys = capturedHighlights.map { highlight in
            QuoteIdentity.importStableQuoteIdentity(
                bookTitle: highlight.bookTitle,
                author: highlight.author,
                location: highlight.location,
                quoteText: highlight.quoteText
            )
        }
        try insertHighlightTombstones(quoteIdentityKeys: quoteIdentityKeys, deletedAt: deletedAt, database: database)

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

    static func makeBulkBookDeletionPlan(bookIDs: [UUID], database: Database) throws -> BulkBookDeletionPlan {
        let capturedBookIDs = try fetchLiveBookIDs(matchingIDs: bookIDs, database: database)
        guard !capturedBookIDs.isEmpty else {
            return BulkBookDeletionPlan(bookIDs: [], linkedHighlights: [])
        }

        let linkedHighlights = try fetchLiveLinkedHighlights(linkedToBookIDs: capturedBookIDs, database: database)
        return BulkBookDeletionPlan(bookIDs: capturedBookIDs, linkedHighlights: linkedHighlights)
    }

    static func deleteBooks(using plan: BulkBookDeletionPlan, database: Database) throws -> LibrarySnapshot {
        let capturedBookIDs = DatabaseBatching.uniqueUUIDStrings(from: plan.bookIDs)
        guard !capturedBookIDs.isEmpty else {
            return try makeLibrarySnapshot(database: database)
        }

        let deletedAt = DatabaseRecordMapper.iso8601Formatter.string(from: Date())
        let quoteIdentityKeys = plan.linkedHighlights.map { linkedHighlight in
            QuoteIdentity.importStableQuoteIdentity(
                bookTitle: linkedHighlight.bookTitle,
                author: linkedHighlight.author,
                location: linkedHighlight.location,
                quoteText: linkedHighlight.quoteText
            )
        }
        try insertHighlightTombstones(quoteIdentityKeys: quoteIdentityKeys, deletedAt: deletedAt, database: database)

        let capturedLinkedHighlightIDs = DatabaseBatching.uniqueUUIDStrings(from: plan.linkedHighlightIDs)
        try deleteRows(
            from: "highlights",
            idColumn: "id",
            ids: capturedLinkedHighlightIDs,
            batchRowLimit: deleteSelectionBatchRowLimit,
            database: database
        )

        try deleteRows(
            from: "books",
            idColumn: "id",
            ids: capturedBookIDs,
            batchRowLimit: deleteSelectionBatchRowLimit,
            database: database
        )

        return try makeLibrarySnapshot(database: database)
    }

    static func fetchAllBooks(database: Database) throws -> [Book] {
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

        return rows.map(DatabaseRecordMapper.book(from:))
    }

    static func totalHighlightCount(database: Database) throws -> Int {
        try Int.fetchOne(
            database,
            sql: """
            SELECT COUNT(*)
            FROM highlights
            """
        ) ?? 0
    }

    static func makeLibrarySnapshot(database: Database) throws -> LibrarySnapshot {
        LibrarySnapshot(
            totalHighlightCount: try totalHighlightCount(database: database),
            books: try fetchAllBooks(database: database)
        )
    }

    static func hasHighlightTombstone(quoteIdentityKey: String, database: Database) throws -> Bool {
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

    static func hasHighlight(dedupeKey: String, database: Database) throws -> Bool {
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

    static func insertHighlightTombstones(
        quoteIdentityKeys: [String],
        deletedAt: String,
        database: Database
    ) throws {
        let uniqueQuoteIdentityKeys = DatabaseBatching.uniqueStringsPreservingOrder(from: quoteIdentityKeys)
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

    private static func fetchLiveHighlights(matchingIDs ids: [UUID], database: Database) throws -> [Highlight] {
        let uniqueHighlightIDs = DatabaseBatching.uniqueUUIDStrings(from: ids)
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
        let uniqueBookIDs = DatabaseBatching.uniqueUUIDStrings(from: ids)
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
        let uniqueBookIDs = DatabaseBatching.uniqueUUIDStrings(from: bookIDs)
        guard !uniqueBookIDs.isEmpty else {
            return []
        }

        var linkedHighlights: [BulkBookDeletionLinkedHighlight] = []

        try DatabaseBatching.forEachStringBatch(
            uniqueBookIDs,
            batchRowLimit: deleteSelectionBatchRowLimit
        ) { bookIDBatch in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT id, bookId, bookTitle, author, location, quoteText
                FROM highlights
                WHERE bookId IN (\(DatabaseBatching.sqlPlaceholders(count: bookIDBatch.count)))
                """,
                arguments: StatementArguments(bookIDBatch)
            )

            linkedHighlights.append(contentsOf: rows.map(DatabaseRecordMapper.linkedHighlight(from:)))
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

        try DatabaseBatching.forEachStringBatch(ids, batchRowLimit: batchRowLimit) { highlightIDBatch in
            let rows = try Row.fetchAll(
                database,
                sql: """
                SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled
                FROM highlights
                WHERE id IN (\(DatabaseBatching.sqlPlaceholders(count: highlightIDBatch.count)))
                """,
                arguments: StatementArguments(highlightIDBatch)
            )

            for row in rows {
                let highlight = DatabaseRecordMapper.highlight(from: row)
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

        try DatabaseBatching.forEachStringBatch(ids, batchRowLimit: batchRowLimit) { bookIDBatch in
            let storedBookIDRows = try Row.fetchAll(
                database,
                sql: """
                SELECT id
                FROM books
                WHERE id IN (\(DatabaseBatching.sqlPlaceholders(count: bookIDBatch.count)))
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

        try DatabaseBatching.forEachStringBatch(ids, batchRowLimit: batchRowLimit) { idBatch in
            try database.execute(
                sql: """
                DELETE FROM \(tableName)
                WHERE \(idColumn) IN (\(DatabaseBatching.sqlPlaceholders(count: idBatch.count)))
                """,
                arguments: StatementArguments(idBatch)
            )
        }
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
}
