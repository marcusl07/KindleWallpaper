import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t97a_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func assertNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs == rhs {
        fail("\(message). Both values were \(lhs)")
    }
}

private func testImportStableIdentityNormalizesCaseAndWhitespace() {
    let first = ImportStableQuoteIdentityKeyBuilder.makeKey(
        bookTitle: "  The Pragmatic Programmer ",
        author: " Andy   Hunt ",
        location: " Loc 123 ",
        quoteText: "  Care about your craft.  "
    )
    let second = ImportStableQuoteIdentityKeyBuilder.makeKey(
        bookTitle: "the pragmatic programmer",
        author: "andy hunt",
        location: "loc 123",
        quoteText: "care   about   your craft."
    )

    assertEqual(first, second, "Import-stable identity should normalize case and repeated whitespace")
}

private func testImportStableIdentityTreatsBlankLocationAsAbsent() {
    let withoutLocation = ImportStableQuoteIdentityKeyBuilder.makeKey(
        bookTitle: "Book",
        author: "Author",
        location: nil,
        quoteText: "Quote"
    )
    let blankLocation = ImportStableQuoteIdentityKeyBuilder.makeKey(
        bookTitle: "Book",
        author: "Author",
        location: "   ",
        quoteText: "Quote"
    )

    assertEqual(withoutLocation, blankLocation, "Blank locations should collapse to the same optional identity")
}

private func testImportStableIdentityUsesFullNormalizedQuoteText() {
    let sharedPrefix = String(repeating: "A", count: 55)
    let first = ImportStableQuoteIdentityKeyBuilder.makeKey(
        bookTitle: "Book",
        author: "Author",
        location: "42",
        quoteText: "\(sharedPrefix) ending one"
    )
    let second = ImportStableQuoteIdentityKeyBuilder.makeKey(
        bookTitle: "Book",
        author: "Author",
        location: "42",
        quoteText: "\(sharedPrefix) ending two"
    )

    assertNotEqual(first, second, "Import-stable identity should use the full normalized quote text, not a prefix")
}

testImportStableIdentityNormalizesCaseAndWhitespace()
testImportStableIdentityTreatsBlankLocationAsAbsent()
testImportStableIdentityUsesFullNormalizedQuoteText()

print("verify_t97a_main passed")
