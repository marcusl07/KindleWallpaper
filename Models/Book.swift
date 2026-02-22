import Foundation

struct Book: Identifiable {
    let id: UUID
    let title: String
    let author: String
    var isEnabled: Bool
    let highlightCount: Int
}
