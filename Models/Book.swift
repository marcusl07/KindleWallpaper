import Foundation

struct Book: Identifiable, Equatable {
    let id: UUID
    let title: String
    let author: String
    var isEnabled: Bool
    let highlightCount: Int
}

struct LibrarySnapshot: Equatable {
    let totalHighlightCount: Int
    let books: [Book]
}
