import Foundation

let testBookID = UUID(uuidString: "A0B1C2D3-E4F5-4678-9123-ABCDEF012345")!

func testPrimaryKeyIncludesNormalizedLocationAndQuotePrefix() {
    let key = ClippingsParser.computeDedupeKey(
        bookId: testBookID,
        location: "  Page   212-213  ",
        quoteText: "  The   Quick  Brown  Fox  "
    )

    assertEqual(
        key,
        "a0b1c2d3-e4f5-4678-9123-abcdef012345|page 212-213|the quick brown fox",
        "Primary key should include normalized location and normalized quote prefix"
    )
}

func testFallbackKeyOmitsLocationSegmentWhenLocationIsNil() {
    let key = ClippingsParser.computeDedupeKey(
        bookId: testBookID,
        location: nil,
        quoteText: "Repeatable quote body"
    )

    assertEqual(
        key,
        "a0b1c2d3-e4f5-4678-9123-abcdef012345|repeatable quote body",
        "Missing location should use fallback key shape without empty location segment"
    )
}

func testFallbackKeyOmitsLocationSegmentWhenLocationIsBlank() {
    let key = ClippingsParser.computeDedupeKey(
        bookId: testBookID,
        location: " \n\t ",
        quoteText: "Repeatable quote body"
    )

    assertEqual(
        key,
        "a0b1c2d3-e4f5-4678-9123-abcdef012345|repeatable quote body",
        "Whitespace-only location should use fallback key shape"
    )
}

func testQuotePrefixIsLimitedToFiftyCharactersAfterNormalization() {
    let key = ClippingsParser.computeDedupeKey(
        bookId: testBookID,
        location: "10-11",
        quoteText: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz12345"
    )

    assertEqual(
        key,
        "a0b1c2d3-e4f5-4678-9123-abcdef012345|10-11|abcdefghijklmnopqrstuvwxyzabcdefghijklmnopqrstuvwx",
        "Quote component should be normalized and capped to first 50 characters"
    )
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message)\nExpected: \(expected)\nActual:   \(actual)\n", stderr)
        exit(1)
    }
}

testPrimaryKeyIncludesNormalizedLocationAndQuotePrefix()
testFallbackKeyOmitsLocationSegmentWhenLocationIsNil()
testFallbackKeyOmitsLocationSegmentWhenLocationIsBlank()
testQuotePrefixIsLimitedToFiftyCharactersAfterNormalization()
print("T15 verification passed")
