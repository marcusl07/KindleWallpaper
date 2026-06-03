import GRDB
import AppKit
import XCTest
@testable import KindleWall

final class DatabaseRepositoryTests: XCTestCase {
    private var rootURL: URL!
    private var databaseQueue: DatabaseQueue!

    override func setUpWithError() throws {
        try super.setUpWithError()
        rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LeafDatabaseTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)

        var configuration = Configuration()
        configuration.foreignKeysEnabled = true
        databaseQueue = try DatabaseQueue(
            path: rootURL.appendingPathComponent("highlights.db").path,
            configuration: configuration
        )
        try DatabaseSchema.initialize(in: databaseQueue)
    }

    override func tearDownWithError() throws {
        databaseQueue = nil
        try? FileManager.default.removeItem(at: rootURL)
        rootURL = nil
        try super.tearDownWithError()
    }

    func testSchemaMigrationOpensDatabaseWithExpectedTablesAndFTSTriggers() throws {
        let (tables, triggers) = try databaseQueue.read { database in
            (
                try String.fetchAll(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name"
                ),
                try String.fetchAll(
                    database,
                    sql: "SELECT name FROM sqlite_master WHERE type = 'trigger' ORDER BY name"
                )
            )
        }

        XCTAssertTrue(tables.contains("books"))
        XCTAssertTrue(tables.contains("highlights"))
        XCTAssertTrue(tables.contains("highlight_tombstones"))
        XCTAssertTrue(tables.contains("highlights_fts"))
        XCTAssertEqual(triggers, ["highlights_ad", "highlights_ai", "highlights_au"])
    }

    func testImportDedupeSkipsDuplicateRowsWithinAndAcrossImports() throws {
        let book = makeBook(title: "The Left Hand of Darkness", author: "Ursula K. Le Guin")
        let firstHighlight = makeHighlight(
            bookID: book.id,
            quoteText: "Light is the left hand of darkness.",
            bookTitle: book.title,
            author: book.author,
            location: "42"
        )
        let duplicateHighlight = makeHighlight(
            bookID: book.id,
            quoteText: "  Light   is the left hand of darkness.  ",
            bookTitle: book.title,
            author: book.author,
            location: "42"
        )

        let firstResult = try databaseQueue.write { database in
            try ImportRepository.persistImport(
                books: [book],
                highlights: [firstHighlight, duplicateHighlight],
                database: database
            )
        }
        let secondResult = try databaseQueue.write { database in
            try ImportRepository.persistImport(books: [book], highlights: [firstHighlight], database: database)
        }

        XCTAssertEqual(firstResult.newHighlightCount, 1)
        XCTAssertEqual(firstResult.librarySnapshot.totalHighlightCount, 1)
        XCTAssertEqual(secondResult.newHighlightCount, 0)
        XCTAssertEqual(secondResult.librarySnapshot.totalHighlightCount, 1)
    }

    func testDeletingHighlightWritesTombstoneAndBlocksReimport() throws {
        let book = makeBook()
        let highlight = makeHighlight(bookID: book.id, location: "99")

        try databaseQueue.write { database in
            _ = try ImportRepository.persistImport(books: [book], highlights: [highlight], database: database)
        }

        let deletionPlan = try databaseQueue.read { database in
            try LibraryRepository.makeBulkHighlightDeletionPlan(highlightIDs: [highlight.id], database: database)
        }
        let deleteSnapshot = try databaseQueue.write { database in
            try LibraryRepository.deleteHighlights(using: deletionPlan, database: database)
        }
        let tombstoneExists = try databaseQueue.read { database in
            try LibraryRepository.hasHighlightTombstone(
                quoteIdentityKey: QuoteIdentity.importStableQuoteIdentity(for: highlight),
                database: database
            )
        }
        let reimportResult = try databaseQueue.write { database in
            try ImportRepository.persistImport(books: [book], highlights: [highlight], database: database)
        }

        XCTAssertEqual(deleteSnapshot.totalHighlightCount, 0)
        XCTAssertTrue(tombstoneExists)
        XCTAssertEqual(reimportResult.newHighlightCount, 0)
        XCTAssertEqual(reimportResult.librarySnapshot.totalHighlightCount, 0)
    }

    func testQuoteSearchHandlesEmptyLongAndPunctuationHeavyInputs() throws {
        let book = makeBook(title: "Collected Essays", author: "Octavia Butler")
        let highlight = makeHighlight(
            bookID: book.id,
            quoteText: "When vision fails, persistence matters.",
            bookTitle: book.title,
            author: book.author,
            location: "7"
        )

        try databaseQueue.write { database in
            _ = try ImportRepository.persistImport(books: [book], highlights: [highlight], database: database)
        }

        let emptySearchCount = try databaseQueue.read { database in
            try QuoteRepository.fetchHighlightsCount(
                searchText: " \n\t ",
                filters: QuotesListFilters(),
                database: database
            )
        }
        let longSearchCount = try databaseQueue.read { database in
            try QuoteRepository.fetchHighlightsCount(
                searchText: String(repeating: "vision ", count: 80),
                filters: QuotesListFilters(),
                database: database
            )
        }
        let punctuationSearchCount = try databaseQueue.read { database in
            try QuoteRepository.fetchHighlightsCount(
                searchText: "!!! \"vision\" -- persistence???",
                filters: QuotesListFilters(),
                database: database
            )
        }

        XCTAssertEqual(emptySearchCount, 1)
        XCTAssertEqual(longSearchCount, 1)
        XCTAssertEqual(punctuationSearchCount, 1)
    }

    func testQuoteSearchHandlesApostrophesHyphensNonASCIIAndMalformedFTSQueries() throws {
        let book = makeBook(title: "The O'Connor Memoirs", author: "München Press")
        let highlight = makeHighlight(
            bookID: book.id,
            quoteText: "It's a self-esteem guide for the modern-day world, written in München & 世界.",
            bookTitle: book.title,
            author: book.author,
            location: "8"
        )

        try databaseQueue.write { database in
            _ = try ImportRepository.persistImport(books: [book], highlights: [highlight], database: database)
        }

        // Test apostrophe
        let apostropheCount = try databaseQueue.read { database in
            try QuoteRepository.fetchHighlightsCount(
                searchText: "O'Connor",
                filters: QuotesListFilters(),
                database: database
            )
        }
        let contractedCount = try databaseQueue.read { database in
            try QuoteRepository.fetchHighlightsCount(
                searchText: "It's",
                filters: QuotesListFilters(),
                database: database
            )
        }

        // Test hyphen
        let hyphenatedCount = try databaseQueue.read { database in
            try QuoteRepository.fetchHighlightsCount(
                searchText: "self-esteem",
                filters: QuotesListFilters(),
                database: database
            )
        }

        // Test non-ASCII text
        let umlautCount = try databaseQueue.read { database in
            try QuoteRepository.fetchHighlightsCount(
                searchText: "München",
                filters: QuotesListFilters(),
                database: database
            )
        }
        let unicodeCount = try databaseQueue.read { database in
            try QuoteRepository.fetchHighlightsCount(
                searchText: "世界",
                filters: QuotesListFilters(),
                database: database
            )
        }

        // Test malformed FTS / raw query that would normally trigger a syntax error (like unclosed quotes or FTS operators)
        let malformedCount = try databaseQueue.read { database in
            try QuoteRepository.fetchHighlightsCount(
                searchText: " * OR \" AND (MATCH) ",
                filters: QuotesListFilters(),
                database: database
            )
        }

        XCTAssertEqual(apostropheCount, 1)
        XCTAssertEqual(contractedCount, 1)
        XCTAssertEqual(hyphenatedCount, 1)
        XCTAssertEqual(umlautCount, 1)
        XCTAssertEqual(unicodeCount, 1)
        XCTAssertEqual(malformedCount, 0) // Should catch syntax error gracefully and return 0
    }

    func testDatabaseOpenFailureThrowsInsteadOfCrashing() throws {
        let invalidDatabaseURL = rootURL.appendingPathComponent("database-directory", isDirectory: false)
        try FileManager.default.createDirectory(at: invalidDatabaseURL, withIntermediateDirectories: false)

        XCTAssertThrowsError(try DatabaseManager.makeDatabaseQueue(databaseURL: invalidDatabaseURL))
    }

    func testImportCoordinatorSurfacesPersistenceFailure() throws {
        let fixtureURL = try writeFixture(named: "My Clippings.txt", contents: "valid input")
        let book = makeBook(title: "Parable of the Sower", author: "Octavia Butler")
        let highlight = makeHighlight(
            bookID: book.id,
            quoteText: "All that you touch you change.",
            bookTitle: book.title,
            author: book.author,
            location: "12"
        )
        let coordinator = ImportCoordinator(
            parseClippings: { _ in
                ClippingsParser.ParseResult(
                    highlights: [highlight],
                    books: [book],
                    parseErrorCount: 0,
                    skippedEntryCount: 1,
                    warningMessages: ["Skipped malformed entry near: \"broken\""],
                    error: nil
                )
            },
            upsertBook: { $0.id },
            insertHighlightIfNew: { _ in },
            totalHighlightCount: { 0 },
            persistImport: { _, _ in
                throw DatabaseManager.DatabaseFailure.operationFailed(
                    operation: "save imported highlights",
                    message: "database is locked"
                )
            }
        )

        let result = coordinator.importFile(at: fixtureURL)

        XCTAssertEqual(result.newHighlightCount, 0)
        XCTAssertEqual(
            result.error,
            "Could not save imported highlights. Leaf could not save imported highlights: database is locked"
        )
        XCTAssertEqual(result.skippedEntryCount, 1)
        XCTAssertEqual(result.warningMessages, ["Skipped malformed entry near: \"broken\""])
        XCTAssertNil(result.librarySnapshot)
    }

    func testWallpaperGeneratorThrowsWhenGeneratedDirectoryCannotBeCreated() throws {
        let blockedDirectoryURL = rootURL.appendingPathComponent("blocked-app-support", isDirectory: true)
        let generatedDirectoryURL = blockedDirectoryURL
            .appendingPathComponent("generated-wallpapers", isDirectory: true)
        try FileManager.default.createDirectory(at: blockedDirectoryURL, withIntermediateDirectories: false)
        try Data("not a directory".utf8).write(to: generatedDirectoryURL)

        let generator = WallpaperGenerator(
            appSupportDirectoryProvider: { blockedDirectoryURL },
            backgroundImageLoader: BackgroundImageLoader(fileManager: .default),
            retainedGeneratedFileCount: 1
        )
        let highlight = makeHighlight(bookID: UUID(), quoteText: "Recoverable file errors should not crash.")
        let target = WallpaperGenerator.RenderTarget(
            identifier: "main",
            pixelWidth: 64,
            pixelHeight: 64
        )

        XCTAssertThrowsError(
            try generator.generateWallpapers(
                highlight: highlight,
                backgroundURL: nil,
                targets: [target],
                rotationID: "phase-5"
            )
        ) { error in
            guard case WallpaperGenerator.GenerationError.createOutputDirectoryFailed = error else {
                return XCTFail("Expected createOutputDirectoryFailed, got \(error)")
            }
        }
    }

    private func makeBook(
        id: UUID = UUID(),
        title: String = "Meditations",
        author: String = "Marcus Aurelius"
    ) -> Book {
        Book(id: id, title: title, author: author, isEnabled: true, highlightCount: 0)
    }

    private func makeHighlight(
        id: UUID = UUID(),
        bookID: UUID,
        quoteText: String = "You have power over your mind.",
        bookTitle: String = "Meditations",
        author: String = "Marcus Aurelius",
        location: String? = nil,
        dateAdded: Date? = Date(timeIntervalSince1970: 1_700_000_000)
    ) -> Highlight {
        Highlight(
            id: id,
            bookId: bookID,
            quoteText: quoteText,
            bookTitle: bookTitle,
            author: author,
            location: location,
            dateAdded: dateAdded,
            lastShownAt: nil
        )
    }

    private func writeFixture(named filename: String, contents: String) throws -> URL {
        let url = rootURL.appendingPathComponent(filename, isDirectory: false)
        try Data(contents.utf8).write(to: url)
        return url
    }
}
