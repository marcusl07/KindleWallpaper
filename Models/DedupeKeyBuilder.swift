import Foundation

enum QuoteIdentityNormalizer {
    static func normalizedComponent(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}

enum DedupeKeyBuilder {
    static func makeKey(bookId: UUID, location: String?, quoteText: String) -> String {
        makeKey(
            bookId: Optional(bookId),
            bookTitle: "",
            author: "",
            location: location,
            quoteText: quoteText
        )
    }

    static func makeKey(
        bookId: UUID?,
        bookTitle: String,
        author: String,
        location: String?,
        quoteText: String
    ) -> String {
        let normalizedIdentity: String
        if let bookId {
            normalizedIdentity = "book|\(bookId.uuidString.lowercased())"
        } else {
            let normalizedTitle = QuoteIdentityNormalizer.normalizedComponent(bookTitle)
            let normalizedAuthor = QuoteIdentityNormalizer.normalizedComponent(author)
            normalizedIdentity = "manual|\(normalizedTitle)|\(normalizedAuthor)"
        }

        let normalizedQuotePrefix = String(QuoteIdentityNormalizer.normalizedComponent(quoteText).prefix(50))
        let normalizedLocation = QuoteIdentityNormalizer.normalizedComponent(location ?? "")

        if normalizedLocation.isEmpty {
            return "\(normalizedIdentity)|\(normalizedQuotePrefix)"
        }

        return "\(normalizedIdentity)|\(normalizedLocation)|\(normalizedQuotePrefix)"
    }
}

enum ImportStableQuoteIdentityKeyBuilder {
    static func makeKey(
        bookTitle: String,
        author: String,
        location: String?,
        quoteText: String
    ) -> String {
        let normalizedTitle = QuoteIdentityNormalizer.normalizedComponent(bookTitle)
        let normalizedAuthor = QuoteIdentityNormalizer.normalizedComponent(author)
        let normalizedQuoteText = QuoteIdentityNormalizer.normalizedComponent(quoteText)
        let normalizedLocation = QuoteIdentityNormalizer.normalizedComponent(location ?? "")

        if normalizedLocation.isEmpty {
            return "import|\(normalizedTitle)|\(normalizedAuthor)|\(normalizedQuoteText)"
        }

        return "import|\(normalizedTitle)|\(normalizedAuthor)|\(normalizedLocation)|\(normalizedQuoteText)"
    }
}
