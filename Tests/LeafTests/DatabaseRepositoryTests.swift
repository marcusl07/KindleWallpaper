import GRDB
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
}
