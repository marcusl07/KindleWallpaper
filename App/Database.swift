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
        }
    }
}
