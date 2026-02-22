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
        bookId      TEXT NOT NULL,
        quoteText   TEXT NOT NULL,
        bookTitle   TEXT NOT NULL,
        author      TEXT NOT NULL,
        location    TEXT,
        dateAdded   TEXT,
        lastShownAt TEXT,
        dedupeKey   TEXT NOT NULL UNIQUE
    );
    """

    private static let createHighlightsBookIDIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_bookId
    ON highlights(bookId);
    """

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func makeDatabaseURL() throws -> URL {
        let fileManager = FileManager.default
        let appSupportURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("KindleWall", isDirectory: true)
        return appSupportURL.appendingPathComponent("highlights.db", isDirectory: false)
    }

    private static func createDirectoryIfNeeded(at url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    private static func initializeSchema(in databaseQueue: DatabaseQueue) throws {
        try databaseQueue.write { database in
            try database.execute(sql: createBooksTableSQL)
            try database.execute(sql: createHighlightsTableSQL)
            try database.execute(sql: createHighlightsBookIDIndexSQL)
        }
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
                        dedupeKey
                    )
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                    arguments: [
                        highlight.id.uuidString,
                        highlight.bookId.uuidString,
                        highlight.quoteText,
                        highlight.bookTitle,
                        highlight.author,
                        highlight.location,
                        iso8601String(from: highlight.dateAdded),
                        iso8601String(from: highlight.lastShownAt),
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

    static func pickNextHighlight() -> Highlight? {
        do {
            return try shared.write { database in
                let activePoolCount = try Int.fetchOne(
                    database,
                    sql: """
                    SELECT COUNT(*)
                    FROM highlights
                    WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1)
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
                    WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1)
                      AND lastShownAt IS NULL
                    """
                ) ?? 0

                if eligibleCount == 0 {
                    try database.execute(
                        sql: """
                        UPDATE highlights
                        SET lastShownAt = NULL
                        WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1)
                        """
                    )

                    eligibleCount = try Int.fetchOne(
                        database,
                        sql: """
                        SELECT COUNT(*)
                        FROM highlights
                        WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1)
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
                    SELECT id, bookId, quoteText, bookTitle, author, location, dateAdded, lastShownAt
                    FROM highlights
                    WHERE bookId IN (SELECT id FROM books WHERE isEnabled = 1)
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

    private static func computeDedupeKey(for highlight: Highlight) -> String {
        let normalizedLocation = normalizedDedupeComponent(highlight.location ?? "")
        let normalizedQuotePrefix = String(normalizedDedupeComponent(highlight.quoteText).prefix(50))
        return "\(highlight.bookId.uuidString.lowercased())|\(normalizedLocation)|\(normalizedQuotePrefix)"
    }

    private static func normalizedDedupeComponent(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
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

        guard
            let bookIDValue: String = row["bookId"],
            let bookID = UUID(uuidString: bookIDValue)
        else {
            fatalError("Invalid highlight bookId in database row")
        }

        let dateAddedValue: String? = row["dateAdded"]
        let lastShownAtValue: String? = row["lastShownAt"]

        return Highlight(
            id: id,
            bookId: bookID,
            quoteText: row["quoteText"],
            bookTitle: row["bookTitle"],
            author: row["author"],
            location: row["location"],
            dateAdded: dateAddedValue.flatMap { iso8601Formatter.date(from: $0) },
            lastShownAt: lastShownAtValue.flatMap { iso8601Formatter.date(from: $0) }
        )
    }
}
