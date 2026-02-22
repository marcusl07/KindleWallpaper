import Foundation

func testParsesExpectedKindleDateFormat() {
    ClippingsParser.resetParseErrorCount()

    let parsed = ClippingsParser.parseKindleDate("Wednesday, May 7, 2025 11:04:04 PM")
    assertTrue(parsed != nil, "Expected valid Kindle date to parse")
    assertEqual(ClippingsParser.parseErrorCount, 0, "Successful parse must not increment parseErrorCount")

    guard let parsed else {
        return
    }

    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .autoupdatingCurrent
    let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: parsed)

    assertEqual(components.year, 2025, "Year mismatch")
    assertEqual(components.month, 5, "Month mismatch")
    assertEqual(components.day, 7, "Day mismatch")
    assertEqual(components.hour, 23, "Hour mismatch for PM input")
    assertEqual(components.minute, 4, "Minute mismatch")
    assertEqual(components.second, 4, "Second mismatch")
}

func testParsesTrimmedInput() {
    ClippingsParser.resetParseErrorCount()

    let parsed = ClippingsParser.parseKindleDate("  Wednesday, May 7, 2025 11:04:04 PM  \n")
    assertTrue(parsed != nil, "Expected parser to handle trimmed whitespace")
    assertEqual(ClippingsParser.parseErrorCount, 0, "Trimmed valid parse should not increment parseErrorCount")
}

func testInvalidDateIncrementsParseErrorCount() {
    ClippingsParser.resetParseErrorCount()

    let parsed = ClippingsParser.parseKindleDate("not-a-kindle-date")
    assertTrue(parsed == nil, "Invalid date input should return nil")
    assertEqual(ClippingsParser.parseErrorCount, 1, "Single invalid parse should increment parseErrorCount once")
}

func testMultipleFailuresAccumulateCount() {
    ClippingsParser.resetParseErrorCount()

    _ = ClippingsParser.parseKindleDate("Wednesday, May 7, 2025 11:04:04 PM")
    _ = ClippingsParser.parseKindleDate("bad input one")
    _ = ClippingsParser.parseKindleDate("Thursday May 8 2025")

    assertEqual(ClippingsParser.parseErrorCount, 2, "Only failing parses should increase parseErrorCount")
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    guard actual == expected else {
        fputs("Assertion failed: \(message)\nExpected: \(expected)\nActual:   \(actual)\n", stderr)
        exit(1)
    }
}

func assertTrue(_ condition: Bool, _ message: String) {
    guard condition else {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

testParsesExpectedKindleDateFormat()
testParsesTrimmedInput()
testInvalidDateIncrementsParseErrorCount()
testMultipleFailuresAccumulateCount()
print("T14 verification passed")
