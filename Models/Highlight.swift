import Foundation

struct Highlight: Identifiable {
    let id: UUID
    let bookId: UUID
    let quoteText: String
    let bookTitle: String
    let author: String
    let location: String?
    let dateAdded: Date?
    var lastShownAt: Date?
    let isEnabled: Bool

    init(
        id: UUID,
        bookId: UUID,
        quoteText: String,
        bookTitle: String,
        author: String,
        location: String?,
        dateAdded: Date?,
        lastShownAt: Date?,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.bookId = bookId
        self.quoteText = quoteText
        self.bookTitle = bookTitle
        self.author = author
        self.location = location
        self.dateAdded = dateAdded
        self.lastShownAt = lastShownAt
        self.isEnabled = isEnabled
    }
}
