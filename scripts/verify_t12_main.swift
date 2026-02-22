import Foundation

func testExtractsValidHighlightChunk() {
    let chunk = """


    Book One (Author One)
    - Your Highlight on page 1 | Location 12-13 | Added on Wednesday, May 7, 2025 11:04:04 PM

    First quote line
    second quote line
    """

    let extracted = ClippingsParser.extractEntryFields(from: [chunk])
    assertEqual(extracted.count, 1, "Expected one extracted chunk")
    assertEqual(extracted[0].titleLine, "Book One (Author One)", "Incorrect title line")
    assertEqual(
        extracted[0].metadataLine,
        "- Your Highlight on page 1 | Location 12-13 | Added on Wednesday, May 7, 2025 11:04:04 PM",
        "Incorrect metadata line"
    )
    assertEqual(extracted[0].quoteBody, "First quote line second quote line", "Incorrect quote body")
}

func testSkipsChunksWithoutHighlightMetadata() {
    let chunks = [
        """
        Book One (Author One)
        - Your Note on page 2 | Added on Wednesday, May 7, 2025 11:04:04 PM

        This is a note.
        """,
        """
        Book Two (Author Two)
        - Your Bookmark on page 7 | Added on Wednesday, May 7, 2025 11:04:04 PM

        """
    ]

    let extracted = ClippingsParser.extractEntryFields(from: chunks)
    assertEqual(extracted.count, 0, "Note and bookmark chunks should be ignored")
}

func testUsesFirstMetadataLine() {
    let chunk = """
    Book Three (Author Three)
    - Your Bookmark on page 1 | Added on Wednesday, May 7, 2025 11:04:04 PM
    - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM

    Real quote text
    """

    let extracted = ClippingsParser.extractEntryFields(from: [chunk])
    assertEqual(extracted.count, 0, "Chunk should be skipped when first metadata line is not a highlight")
}

func testRequiresBlankLineAfterMetadata() {
    let chunk = """
    Book Four (Author Four)
    - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM
    Quote starts immediately without separator
    """

    let extracted = ClippingsParser.extractEntryFields(from: [chunk])
    assertEqual(extracted.count, 0, "Chunk should be skipped when no blank line follows metadata")
}

func testSkipsEmptyQuoteBodies() {
    let chunk = """
    Book Five (Author Five)
    - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM


     
    """

    let extracted = ClippingsParser.extractEntryFields(from: [chunk])
    assertEqual(extracted.count, 0, "Chunk should be skipped when quote body is empty")
}

func testExtractsAfterFirstBlankFollowingMetadata() {
    let chunk = """
    Book Six (Author Six)
    - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM
    metadata continuation text

    Final quote body
    """

    let extracted = ClippingsParser.extractEntryFields(from: [chunk])
    assertEqual(extracted.count, 1, "Chunk should parse once blank separator is found")
    assertEqual(extracted[0].quoteBody, "Final quote body", "Quote body should start after the first blank line")
}

func testIntegratesWithSplitRawEntries() {
    let raw = """
    Book A (Author A)
    - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM

    Highlight A
    ==========
    Book B (Author B)
    - Your Note on page 1 | Added on Wednesday, May 7, 2025 11:04:04 PM

    Note B
    ==========
    """

    let chunks = ClippingsParser.splitRawEntries(raw)
    let extracted = ClippingsParser.extractEntryFields(from: chunks)
    assertEqual(extracted.count, 1, "Only highlight chunks should survive extraction")
    assertEqual(extracted[0].titleLine, "Book A (Author A)", "Wrong chunk survived extraction")
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message)\nExpected: \(expected)\nActual:   \(actual)\n", stderr)
        exit(1)
    }
}

testExtractsValidHighlightChunk()
testSkipsChunksWithoutHighlightMetadata()
testUsesFirstMetadataLine()
testRequiresBlankLineAfterMetadata()
testSkipsEmptyQuoteBodies()
testExtractsAfterFirstBlankFollowingMetadata()
testIntegratesWithSplitRawEntries()
print("T12 verification passed")
