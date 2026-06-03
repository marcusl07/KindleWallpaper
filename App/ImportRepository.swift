import Foundation
import GRDB

enum ImportRepository {
    private static let importPreflightBatchRowLimit = 400
    private static let importBookUpsertBatchRowLimit = 200
    private static let importHighlightInsertBatchRowLimit = 90

    private struct ImportHighlightInsertRow {
        let highlight: Highlight
        let quoteIdentityKey: String
        let dedupeKey: String
    }

    static func persistImport(
        books: [Book],
        highlights: [Highlight],
        database: Database
    ) throws -> ImportPersistenceResult {
        let persistedBookIDsByParsedID = try bulkUpsertBooksForImport(books, database: database)

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
                    quoteIdentityKey: QuoteIdentity.importStableQuoteIdentity(for: persistedHighlight),
                    dedupeKey: QuoteIdentity.dedupeKey(for: persistedHighlight)
                )
            )
        }

        let persistedHighlights = importHighlightRows.map(\.highlight)
        let existingTombstoneIdentityKeys = try fetchExistingImportTombstoneIdentityKeys(
            for: persistedHighlights,
            database: database
        )
        var knownDedupeKeys = try fetchExistingHighlightDedupeKeys(for: persistedHighlights, database: database)

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
            librarySnapshot: try LibraryRepository.makeLibrarySnapshot(database: database)
        )
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

            let persistedBatchBookIDs = try fetchPersistedImportBookIDs(for: bookBatch, database: database)
            persistedBookIDsByParsedID.merge(persistedBatchBookIDs) { _, rhs in rhs }

            guard persistedBatchBookIDs.count == bookBatch.count else {
                throw DatabaseRepositoryError.unresolvedImportBooks(
                    expected: bookBatch.count,
                    actual: persistedBatchBookIDs.count
                )
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
                throw DatabaseRepositoryError.invalidStoredUUID(field: "imported book id", value: nil)
            }

            persistedBookIDsByParsedID[parsedBookID] = storedBookID
        }

        return persistedBookIDsByParsedID
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
                arguments.append(DatabaseRecordMapper.iso8601String(from: highlight.dateAdded))
                arguments.append(DatabaseRecordMapper.iso8601String(from: highlight.lastShownAt))
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

    private static func fetchExistingImportTombstoneIdentityKeys(
        for highlights: [Highlight],
        database: Database
    ) throws -> Set<String> {
        let quoteIdentityKeys = DatabaseBatching.uniqueStringsPreservingOrder(from: highlights.map {
            QuoteIdentity.importStableQuoteIdentity(for: $0)
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
                WHERE quoteIdentityKey IN (\(DatabaseBatching.sqlPlaceholders(count: quoteIdentityKeyBatch.count)))
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
        let dedupeKeys = DatabaseBatching.uniqueStringsPreservingOrder(from: highlights.map {
            QuoteIdentity.dedupeKey(for: $0)
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
                WHERE dedupeKey IN (\(DatabaseBatching.sqlPlaceholders(count: dedupeKeyBatch.count)))
                """,
                arguments: StatementArguments(dedupeKeyBatch)
            )
            existingDedupeKeys.formUnion(existingBatchKeys)
            batchStartIndex = batchEndIndex
        }

        return existingDedupeKeys
    }
}
