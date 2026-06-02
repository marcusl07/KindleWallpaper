import GRDB

enum DatabaseSchema {
    static let createBooksTableSQL = """
    CREATE TABLE IF NOT EXISTS books (
        id          TEXT PRIMARY KEY,
        title       TEXT NOT NULL,
        author      TEXT NOT NULL,
        isEnabled   INTEGER NOT NULL DEFAULT 1,
        UNIQUE(title, author)
    );
    """

    static let createHighlightsTableSQL = """
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

    static let createHighlightsBookIDIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_bookId
    ON highlights(bookId);
    """

    static let createHighlightsBookIDLastShownAtIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_bookId_lastShownAt
    ON highlights(bookId, lastShownAt);
    """

    static let createHighlightsBookTitleIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_bookTitle_nocase
    ON highlights(bookTitle COLLATE NOCASE);
    """

    static let createHighlightsAuthorIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_author_nocase
    ON highlights(author COLLATE NOCASE);
    """

    static let createHighlightsDateAddedIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_dateAdded
    ON highlights(dateAdded);
    """

    static let createHighlightsAlphabeticalSortIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_alphabetical_sort
    ON highlights(
        bookTitle COLLATE NOCASE,
        author COLLATE NOCASE,
        quoteText COLLATE NOCASE,
        id
    );
    """

    static let createHighlightsMostRecentSortIndexSQL = """
    CREATE INDEX IF NOT EXISTS idx_highlights_most_recent_sort
    ON highlights(
        dateAdded DESC,
        bookTitle COLLATE NOCASE,
        author COLLATE NOCASE,
        quoteText COLLATE NOCASE,
        id
    );
    """

    static let createHighlightsMostRecentNonNullSortIndexSQL = """
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

    static let createHighlightTombstonesTableSQL = """
    CREATE TABLE IF NOT EXISTS highlight_tombstones (
        quoteIdentityKey TEXT PRIMARY KEY,
        deletedAt        TEXT NOT NULL
    );
    """

    static let createHighlightsFTSTableSQL = """
    CREATE VIRTUAL TABLE IF NOT EXISTS highlights_fts USING fts5(
        quoteText,
        bookTitle,
        author,
        content='highlights'
    );
    """

    static let populateHighlightsFTSSQL = """
    INSERT INTO highlights_fts(rowid, quoteText, bookTitle, author)
    SELECT rowid, quoteText, bookTitle, author FROM highlights;
    """

    static let createHighlightsFTSInsertTriggerSQL = """
    CREATE TRIGGER IF NOT EXISTS highlights_ai AFTER INSERT ON highlights BEGIN
        INSERT INTO highlights_fts(rowid, quoteText, bookTitle, author)
        VALUES (new.rowid, new.quoteText, new.bookTitle, new.author);
    END;
    """

    static let createHighlightsFTSDeleteTriggerSQL = """
    CREATE TRIGGER IF NOT EXISTS highlights_ad AFTER DELETE ON highlights BEGIN
        INSERT INTO highlights_fts(highlights_fts, rowid, quoteText, bookTitle, author)
        VALUES ('delete', old.rowid, old.quoteText, old.bookTitle, old.author);
    END;
    """

    static let createHighlightsFTSUpdateTriggerSQL = """
    CREATE TRIGGER IF NOT EXISTS highlights_au AFTER UPDATE ON highlights BEGIN
        INSERT INTO highlights_fts(highlights_fts, rowid, quoteText, bookTitle, author)
        VALUES ('delete', old.rowid, old.quoteText, old.bookTitle, old.author);
        INSERT INTO highlights_fts(rowid, quoteText, bookTitle, author)
        VALUES (new.rowid, new.quoteText, new.bookTitle, new.author);
    END;
    """

    static func initialize(in databaseQueue: DatabaseQueue) throws {
        try DatabaseMigrations.migrate(databaseQueue)
    }

    static func createHighlightsIndexes(in database: Database) throws {
        try database.execute(sql: createHighlightsBookIDIndexSQL)
        try database.execute(sql: createHighlightsBookIDLastShownAtIndexSQL)
        try database.execute(sql: createHighlightsBookTitleIndexSQL)
        try database.execute(sql: createHighlightsAuthorIndexSQL)
        try database.execute(sql: createHighlightsDateAddedIndexSQL)
        try createHighlightsPageIndexes(in: database)
    }

    static func createHighlightsPageIndexes(in database: Database) throws {
        try database.execute(sql: createHighlightsAlphabeticalSortIndexSQL)
        try database.execute(sql: createHighlightsMostRecentSortIndexSQL)
        try database.execute(sql: createHighlightsMostRecentNonNullSortIndexSQL)
    }

}
