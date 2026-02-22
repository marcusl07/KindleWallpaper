import Foundation

@main
struct VerifyT11Main {
    static func main() {
        testCRLFAndTrimmedSeparators()
        testEmptyChunksDropped()
        testNoSeparatorSingleChunk()
        testSeparatorOnlyWhenWholeTrimmedLine()
        print("T11 verification passed")
    }

    private static func testCRLFAndTrimmedSeparators() {
        let chunkOne = """
        Book One (Author One)
        - Your Highlight on page 1 | Location 1-2 | Added on Wednesday, May 7, 2025 11:04:04 PM

        First quote line
        second line
        """

        let chunkTwo = """
        Book Two (Author Two)
        - Your Highlight on page 2 | Location 3-4 | Added on Thursday, May 8, 2025 11:04:04 PM

        Second quote
        """

        let lfInput = chunkOne + "\n   ==========   \n\n" + chunkTwo + "\n==========\n"
        let input = lfInput.replacingOccurrences(of: "\n", with: "\r\n")
        assertEqual(
            ClippingsParser.splitRawEntries(input),
            [chunkOne, chunkTwo],
            "CRLF normalization and trimmed separator splitting failed"
        )
    }

    private static func testEmptyChunksDropped() {
        let input = """
        ==========
           ==========
        Chunk A
        ==========

           
        ==========
        Chunk B
        """
        assertEqual(
            ClippingsParser.splitRawEntries(input),
            ["Chunk A", "Chunk B"],
            "Empty chunks should be discarded"
        )
    }

    private static func testNoSeparatorSingleChunk() {
        let input = """


        Single Chunk
        line2


        """
        assertEqual(
            ClippingsParser.splitRawEntries(input),
            ["Single Chunk\nline2"],
            "Input with no separators should return one trimmed chunk"
        )
    }

    private static func testSeparatorOnlyWhenWholeTrimmedLine() {
        let input = """
        alpha
        not==========separator
        beta
        ==========
        gamma
        """
        assertEqual(
            ClippingsParser.splitRawEntries(input),
            ["alpha\nnot==========separator\nbeta", "gamma"],
            "Separator should only split when the trimmed line exactly matches"
        )
    }

    private static func assertEqual(_ actual: [String], _ expected: [String], _ message: String) {
        guard actual == expected else {
            fputs("Assertion failed: \(message)\nExpected: \(expected)\nActual:   \(actual)\n", stderr)
            exit(1)
        }
    }
}
