import Foundation

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
            let normalizedTitle = normalizedComponent(bookTitle)
            let normalizedAuthor = normalizedComponent(author)
            normalizedIdentity = "manual|\(normalizedTitle)|\(normalizedAuthor)"
        }

        let normalizedQuotePrefix = String(normalizedComponent(quoteText).prefix(50))
        let normalizedLocation = normalizedComponent(location ?? "")

        if normalizedLocation.isEmpty {
            return "\(normalizedIdentity)|\(normalizedQuotePrefix)"
        }

        return "\(normalizedIdentity)|\(normalizedLocation)|\(normalizedQuotePrefix)"
    }

    private static func normalizedComponent(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
