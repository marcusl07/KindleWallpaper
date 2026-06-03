import Foundation
import GRDB
import OSLog

enum QuoteRepository {
    private static let quotesPerformanceSignposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.marcuslo.KindleWall",
        category: "QuotesPerformance"
    )

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

    private static let alphabeticalHighlightsOrderClause = """
    bookTitle COLLATE NOCASE ASC,
    author COLLATE NOCASE ASC,
    quoteText COLLATE NOCASE ASC,
    id ASC
    """

    private enum QuotesFilterOptionField {
        case bookTitle
        case author
    }

    static func fetchAllHighlights(
        sortedBy sortMode: QuotesListSortMode,
        databaseQueue: DatabaseQueue
    ) throws -> [Highlight] {
        let signpostState = quotesPerformanceSignposter.beginInterval(
            "QuotesDBFetch",
            "sortMode=\(sortMode.rawValue, privacy: .public)"
        )

        do {
            let highlights = try databaseQueue.read { database in
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                    SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled
                    FROM highlights
                    ORDER BY \(highlightsOrderClause(sortedBy: sortMode))
                    """
                )

                return try rows.map { row in
                    try DatabaseRecordMapper.highlight(from: row)
                }
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
            throw error
        }
    }

    static func fetchHighlightsPage(
        searchText: String,
        filters: QuotesListFilters,
        sortedBy sortMode: QuotesListSortMode,
        limit: Int,
        offset: Int,
        databaseQueue: DatabaseQueue
    ) throws -> [Highlight] {
        guard limit > 0, offset >= 0 else {
            return []
        }

        let signpostState = quotesPerformanceSignposter.beginInterval(
            "QuotesDBPageFetch",
            "sortMode=\(sortMode.rawValue, privacy: .public) limit=\(limit) offset=\(offset)"
        )

        do {
            let highlights = try databaseQueue.read { database in
                try fetchHighlightsPage(
                    searchText: searchText,
                    filters: filters,
                    sortedBy: sortMode,
                    limit: limit,
                    offset: offset,
                    database: database
                )
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
            throw error
        }
    }

    static func fetchHighlightPagePayload(
        searchText: String,
        filters: QuotesListFilters,
        sortedBy sortMode: QuotesListSortMode,
        limit: Int,
        offset: Int,
        databaseQueue: DatabaseQueue
    ) throws -> QuotesPagePayload {
        guard limit > 0, offset >= 0 else {
            return QuotesPagePayload(highlights: [], totalMatchingHighlightCount: 0)
        }

        let signpostState = quotesPerformanceSignposter.beginInterval(
            "QuotesDBPagePayloadFetch",
            "sortMode=\(sortMode.rawValue, privacy: .public) limit=\(limit) offset=\(offset)"
        )

        do {
            let payload = try databaseQueue.read { database in
                let totalMatchingHighlightCount = try fetchHighlightsCount(
                    searchText: searchText,
                    filters: filters,
                    database: database
                )
                let highlights = try fetchHighlightsPage(
                    searchText: searchText,
                    filters: filters,
                    sortedBy: sortMode,
                    limit: limit,
                    offset: offset,
                    database: database
                )

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
            throw error
        }
    }

    static func fetchHighlightFilterOptions(
        searchText: String,
        filters: QuotesListFilters,
        databaseQueue: DatabaseQueue
    ) throws -> QuotesFilterOptionsPayload {
        try databaseQueue.read { database in
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
    }

    static func fetchAvailableHighlightBookTitles(
        searchText: String,
        filters: QuotesListFilters,
        databaseQueue: DatabaseQueue
    ) throws -> [String] {
        try databaseQueue.read { database in
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
    }

    static func fetchAvailableHighlightAuthors(
        searchText: String,
        filters: QuotesListFilters,
        databaseQueue: DatabaseQueue
    ) throws -> [String] {
        try databaseQueue.read { database in
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
    }

    static func countHighlights(
        searchText: String,
        filters: QuotesListFilters,
        databaseQueue: DatabaseQueue
    ) throws -> Int {
        try databaseQueue.read { database in
            try fetchHighlightsCount(
                searchText: searchText,
                filters: filters,
                database: database
            )
        }
    }

    static func fetchHighlightsCount(
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

    private static func fetchHighlightsPage(
        searchText: String,
        filters: QuotesListFilters,
        sortedBy sortMode: QuotesListSortMode,
        limit: Int,
        offset: Int,
        database: Database
    ) throws -> [Highlight] {
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
            return try rows.map { row in
                try DatabaseRecordMapper.highlight(from: row)
            }
        }
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
        return try rows.map { row in
            try DatabaseRecordMapper.highlight(from: row)
        }
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

        if let ftsQuery = normalizedFTSSearchQuery(for: searchText) {
            conditions.append("highlights.rowid IN (SELECT rowid FROM highlights_fts WHERE highlights_fts MATCH ?)")
            arguments += [ftsQuery]
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

    private static func normalizedFTSSearchQuery(for rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        let words = trimmedValue
            .split { character in
                !character.isLetter && !character.isNumber
            }
            .prefix(16)
            .map(String.init)
            .filter { !$0.isEmpty }

        guard !words.isEmpty else {
            return nil
        }

        let queryParts = words.map { "\"\($0)\"*" }
        return queryParts.joined(separator: " AND ")
    }
}
