import Foundation

func testStandardFormatUsesFinalParenthesizedAuthor() {
    let result = ClippingsParser.cleanTitleAndAuthor(from: "Book Title (Author Name)")
    assertEqual(result.title, "Book Title", "Standard title should remove trailing author parentheses")
    assertEqual(result.author, "Author Name", "Standard format should extract author from trailing parentheses")
}

func testStandardFormatPreservesInnerParentheses() {
    let result = ClippingsParser.cleanTitleAndAuthor(from: "Series Name (Volume 1) (Jane Doe)")
    assertEqual(result.title, "Series Name (Volume 1)", "Only the final parenthesized group should be treated as author")
    assertEqual(result.author, "Jane Doe", "Final parenthesized group should be parsed as author")
}

func testSideloadedFormatFallsBackToFirstDashSegment() {
    let result = ClippingsParser.cleanTitleAndAuthor(from: "Book Title -- Author;Editor -- Publisher -- Extra")
    assertEqual(result.title, "Book Title", "Sideloaded title should stop at the first separator")
    assertEqual(result.author, "Author;Editor", "Sideloaded format should use the first segment after the separator as author fallback")
}

func testSideloadedFormatPrefersFinalParenthesizedGroup() {
    let result = ClippingsParser.cleanTitleAndAuthor(from: "Book Title -- Fallback Author -- Publisher (Final Author)")
    assertEqual(result.title, "Book Title", "Title should still use text before the first separator")
    assertEqual(result.author, "Final Author", "Final parenthesized group should override sideload fallback author")
}

func testNormalizesWhitespaceAcrossFields() {
    let result = ClippingsParser.cleanTitleAndAuthor(from: "  Book   Title   --   Author   Name   --   Publisher   ")
    assertEqual(result.title, "Book Title", "Title whitespace should be normalized")
    assertEqual(result.author, "Author Name", "Author whitespace should be normalized")
}

func testUsesUnknownAuthorFallbackWhenNoAuthorPresent() {
    let result = ClippingsParser.cleanTitleAndAuthor(from: "Lonely Title")
    assertEqual(result.title, "Lonely Title", "Title should remain when no separators or parentheses are present")
    assertEqual(result.author, "Unknown Author", "Missing author should use deterministic fallback")
}

func testUsesUnknownFallbacksForEmptyInput() {
    let result = ClippingsParser.cleanTitleAndAuthor(from: "   ")
    assertEqual(result.title, "Unknown Title", "Empty input should produce fallback title")
    assertEqual(result.author, "Unknown Author", "Empty input should produce fallback author")
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message)\nExpected: \(expected)\nActual:   \(actual)\n", stderr)
        exit(1)
    }
}

testStandardFormatUsesFinalParenthesizedAuthor()
testStandardFormatPreservesInnerParentheses()
testSideloadedFormatFallsBackToFirstDashSegment()
testSideloadedFormatPrefersFinalParenthesizedGroup()
testNormalizesWhitespaceAcrossFields()
testUsesUnknownAuthorFallbackWhenNoAuthorPresent()
testUsesUnknownFallbacksForEmptyInput()
print("T13 verification passed")
