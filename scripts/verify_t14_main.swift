import Foundation

func testParsesExpectedKindleDateFormat() {
    let parsed = ClippingsParser.parseKindleDate("Wednesday, May 7, 2025 11:04:04 PM")
    assertTrue(parsed != nil, "Expected valid Kindle date to parse")

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
    let parsed = ClippingsParser.parseKindleDate("  Wednesday, May 7, 2025 11:04:04 PM  \n")
    assertTrue(parsed != nil, "Expected parser to handle trimmed whitespace")
}

func testInvalidDateReturnsNil() {
    let parsed = ClippingsParser.parseKindleDate("not-a-kindle-date")
    assertTrue(parsed == nil, "Invalid date input should return nil")
}

func testMultipleInvalidInputsRemainStateless() {
    let first = ClippingsParser.parseKindleDate("bad input one")
    let second = ClippingsParser.parseKindleDate("Thursday May 8 2025")
    assertTrue(first == nil && second == nil, "Invalid inputs should consistently return nil without shared parser state")
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
testInvalidDateReturnsNil()
testMultipleInvalidInputsRemainStateless()
print("T14 verification passed")
