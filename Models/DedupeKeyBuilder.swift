import Foundation

enum DedupeKeyBuilder {
    static func makeKey(bookId: UUID, location: String?, quoteText: String) -> String {
        let normalizedBookID = bookId.uuidString.lowercased()
        let normalizedQuotePrefix = String(normalizedComponent(quoteText).prefix(50))
        let normalizedLocation = normalizedComponent(location ?? "")

        if normalizedLocation.isEmpty {
            return "\(normalizedBookID)|\(normalizedQuotePrefix)"
        }

        return "\(normalizedBookID)|\(normalizedLocation)|\(normalizedQuotePrefix)"
    }

    private static func normalizedComponent(_ value: String) -> String {
        value
            .lowercased()
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
    }
}
