import Foundation
import GRDB

enum DatabaseManager {
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

    private static let activeHighlightsPredicateSQL = """
    (bookId IS NULL OR bookId IN (SELECT id FROM books WHERE isEnabled = 1))
      AND isEnabled = 1
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
            try database.execute(sql: createHighlightsBookIDIndexSQL)
            try database.execute(sql: createHighlightsBookIDLastShownAtIndexSQL)
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
            try database.execute(sql: createHighlightsBookIDIndexSQL)
            try database.execute(sql: createHighlightsBookIDLastShownAtIndexSQL)
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

    private static func tableColumnNames(in tableName: String, database: Database) throws -> Set<String> {
        let rows = try Row.fetchAll(database, sql: "PRAGMA table_info(\(tableName))")
        return Set(rows.compactMap { row in
            row["name"] as String?
        })
    }

    static func upsertBook(_ book: Book) -> UUID {
        do {
            return try shared.write { database in
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
        } catch {
            fatalError("Failed to upsert book: \(error)")
        }
    }

    static func insertHighlightIfNew(_ highlight: Highlight) {
        do {
            try shared.write { database in
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
                    return
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

    static func deleteHighlight(id: UUID) {
        do {
            try shared.write { database in
                try database.execute(
                    sql: """
                    DELETE FROM highlights
                    WHERE id = ?
                    """,
                    arguments: [id.uuidString]
                )
            }
        } catch {
            fatalError("Failed to delete highlight: \(error)")
        }
    }

    static func fetchAllBooks() -> [Book] {
        do {
            return try shared.read { database in
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
        } catch {
            fatalError("Failed to fetch all books: \(error)")
        }
    }

    static func fetchAllHighlights() -> [Highlight] {
        do {
            return try shared.read { database in
                let rows = try Row.fetchAll(
                    database,
                    sql: """
                    SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt, isEnabled
                    FROM highlights
                    ORDER BY
                        CASE WHEN dateAdded IS NULL THEN 1 ELSE 0 END ASC,
                        dateAdded DESC,
                        bookTitle COLLATE NOCASE ASC,
                        author COLLATE NOCASE ASC,
                        quoteText COLLATE NOCASE ASC
                    """
                )

                return rows.map(highlight(from:))
            }
        } catch {
            fatalError("Failed to fetch all highlights: \(error)")
        }
    }

    static func totalHighlightCount() -> Int {
        do {
            return try shared.read { database in
                try Int.fetchOne(
                    database,
                    sql: """
                    SELECT COUNT(*)
                    FROM highlights
                    """
                ) ?? 0
            }
        } catch {
            fatalError("Failed to fetch total highlight count: \(error)")
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

    private static func iso8601String(from date: Date?) -> String? {
        guard let date else {
            return nil
        }
        return iso8601Formatter.string(from: date)
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
