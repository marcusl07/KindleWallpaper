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
}
