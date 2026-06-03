import Foundation
import GRDB

enum DatabaseRepositoryError: Error, LocalizedError {
    case missingExpectedRow(String)
    case invalidStoredUUID(field: String, value: String?)
    case unresolvedImportBooks(expected: Int, actual: Int)
    case randomSelectionMissing(offset: Int)

    var errorDescription: String? {
        switch self {
        case .missingExpectedRow(let context):
            return "Missing expected database row while \(context)."
        case .invalidStoredUUID(let field, let value):
            return "Invalid UUID stored for \(field): \(value ?? "nil")."
        case .unresolvedImportBooks(let expected, let actual):
            return "Resolved \(actual) of \(expected) imported book rows."
        case .randomSelectionMissing(let offset):
            return "Could not load quote at random offset \(offset)."
        }
    }
}

enum DatabaseBatching {
    static func uniqueUUIDStrings(from ids: [UUID]) -> [String] {
        var seen = Set<UUID>()
        return ids.compactMap { id in
            guard seen.insert(id).inserted else {
                return nil
            }
            return id.uuidString
        }
    }

    static func uniqueStringsPreservingOrder(from values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            guard seen.insert(value).inserted else {
                return nil
            }
            return value
        }
    }

    static func sqlPlaceholders(count: Int) -> String {
        Array(repeating: "?", count: count).joined(separator: ", ")
    }

    static func forEachStringBatch(
        _ values: [String],
        batchRowLimit: Int,
        body: ([String]) throws -> Void
    ) throws {
        guard !values.isEmpty else {
            return
        }

        var batchStartIndex = 0
        while batchStartIndex < values.count {
            let batchEndIndex = min(batchStartIndex + batchRowLimit, values.count)
            try body(Array(values[batchStartIndex..<batchEndIndex]))
            batchStartIndex = batchEndIndex
        }
    }
}

enum QuoteIdentity {
    static func dedupeKey(for highlight: Highlight) -> String {
        DedupeKeyBuilder.makeKey(
            bookId: highlight.bookId,
            bookTitle: highlight.bookTitle,
            author: highlight.author,
            location: highlight.location,
            quoteText: highlight.quoteText
        )
    }

    static func importStableQuoteIdentity(
        bookTitle: String,
        author: String,
        location: String?,
        quoteText: String
    ) -> String {
        ImportStableQuoteIdentityKeyBuilder.makeKey(
            bookTitle: bookTitle,
            author: author,
            location: location,
            quoteText: quoteText
        )
    }

    static func importStableQuoteIdentity(for highlight: Highlight) -> String {
        importStableQuoteIdentity(
            bookTitle: highlight.bookTitle,
            author: highlight.author,
            location: highlight.location,
            quoteText: highlight.quoteText
        )
    }
}

enum DatabaseRecordMapper {
    static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func iso8601String(from date: Date?) -> String? {
        guard let date else {
            return nil
        }
        return iso8601Formatter.string(from: date)
    }

    static func highlight(from row: Row) throws -> Highlight {
        guard
            let idValue: String = row["id"],
            let id = UUID(uuidString: idValue)
        else {
            throw DatabaseRepositoryError.invalidStoredUUID(field: "highlight id", value: row["id"])
        }

        let bookIDValue: String? = row["bookId"]
        let bookID = bookIDValue.flatMap { UUID(uuidString: $0) }

        if bookIDValue != nil && bookID == nil {
            throw DatabaseRepositoryError.invalidStoredUUID(field: "highlight bookId", value: bookIDValue)
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

    static func book(from row: Row) throws -> Book {
        guard
            let idValue: String = row["id"],
            let id = UUID(uuidString: idValue)
        else {
            throw DatabaseRepositoryError.invalidStoredUUID(field: "book id", value: row["id"])
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

    static func linkedHighlight(from row: Row) throws -> BulkBookDeletionLinkedHighlight {
        guard
            let idValue: String = row["id"],
            let id = UUID(uuidString: idValue)
        else {
            throw DatabaseRepositoryError.invalidStoredUUID(field: "linked highlight id", value: row["id"])
        }

        let bookIDValue: String? = row["bookId"]
        let bookID = bookIDValue.flatMap { UUID(uuidString: $0) }

        if bookIDValue != nil && bookID == nil {
            throw DatabaseRepositoryError.invalidStoredUUID(field: "linked highlight bookId", value: bookIDValue)
        }

        return BulkBookDeletionLinkedHighlight(
            id: id,
            bookID: bookID,
            bookTitle: row["bookTitle"],
            author: row["author"],
            location: row["location"],
            quoteText: row["quoteText"]
        )
    }
}
