import Foundation

struct BulkBookDeletionLinkedHighlight: Equatable {
    let id: UUID
    let bookTitle: String
    let author: String
    let location: String?
    let quoteText: String
}

struct BulkBookDeletionPlan: Equatable {
    let bookIDs: [UUID]
    let linkedHighlights: [BulkBookDeletionLinkedHighlight]

    var bookCount: Int {
        bookIDs.count
    }

    var linkedHighlightIDs: [UUID] {
        linkedHighlights.map(\.id)
    }

    var linkedHighlightCount: Int {
        linkedHighlights.count
    }
}
