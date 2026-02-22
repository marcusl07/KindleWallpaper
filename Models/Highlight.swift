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
}
