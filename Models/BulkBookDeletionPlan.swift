import Foundation

struct BulkHighlightDeletionTarget: Equatable {
    let id: UUID
    let bookTitle: String
    let author: String
    let location: String?
    let quoteText: String
}

struct BulkHighlightDeletionPlan: Equatable {
    let highlights: [BulkHighlightDeletionTarget]

    var highlightIDs: [UUID] {
        highlights.map(\.id)
    }

    var highlightCount: Int {
        highlights.count
    }

    var isEmpty: Bool {
        highlights.isEmpty
    }

    func filtered(validHighlightIDs: Set<UUID>) -> BulkHighlightDeletionPlan {
        BulkHighlightDeletionPlan(
            highlights: highlights.filter { validHighlightIDs.contains($0.id) }
        )
    }
}

struct BulkBookDeletionLinkedHighlight: Equatable {
    let id: UUID
    let bookID: UUID?
    let bookTitle: String
    let author: String
    let location: String?
    let quoteText: String

    init(
        id: UUID,
        bookID: UUID? = nil,
        bookTitle: String,
        author: String,
        location: String?,
        quoteText: String
    ) {
        self.id = id
        self.bookID = bookID
        self.bookTitle = bookTitle
        self.author = author
        self.location = location
        self.quoteText = quoteText
    }
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

    var isEmpty: Bool {
        bookIDs.isEmpty
    }

    func filtered(validBookIDs: Set<UUID>) -> BulkBookDeletionPlan {
        let remainingBookIDs = bookIDs.filter(validBookIDs.contains)
        let remainingBookIDSet = Set(remainingBookIDs)

        return BulkBookDeletionPlan(
            bookIDs: remainingBookIDs,
            linkedHighlights: linkedHighlights.filter { linkedHighlight in
                guard let bookID = linkedHighlight.bookID else {
                    return false
                }

                return remainingBookIDSet.contains(bookID)
            }
        )
    }
}
