import Foundation

enum ClippingsParser {
    private static let separator = "=========="
    private static let kindleDateFormat = "EEEE, MMMM d, yyyy h:mm:ss a"
    private static let kindleDateLocaleIdentifier = "en_US_POSIX"
    private static let kindleDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: kindleDateLocaleIdentifier)
        formatter.timeZone = .autoupdatingCurrent
        formatter.dateFormat = kindleDateFormat
        return formatter
    }()

    private(set) static var parseErrorCount = 0

    struct ExtractedChunk: Equatable {
        let titleLine: String
        let metadataLine: String
        let quoteBody: String
    }

    private struct ParsedBookKey: Hashable {
        let title: String
        let author: String
    }

    private struct ParsedBookRecord {
        let id: UUID
        var highlightCount: Int
    }

    static func splitRawEntries(_ raw: String) -> [String] {
        let normalized = raw.replacingOccurrences(of: "\r\n", with: "\n")
        var chunks: [String] = []
        var currentLines: [Substring] = []
        currentLines.reserveCapacity(8)

        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.trimmingCharacters(in: .whitespacesAndNewlines) == separator {
                appendChunk(from: currentLines, into: &chunks)
                currentLines.removeAll(keepingCapacity: true)
                continue
            }
            currentLines.append(line)
        }

        appendChunk(from: currentLines, into: &chunks)
        return chunks
    }

    static func extractEntryFields(from chunks: [String]) -> [ExtractedChunk] {
        chunks.compactMap(extractEntryFields(from:))
    }

    static func cleanTitleAndAuthor(from titleLine: String) -> (title: String, author: String) {
        let normalizedLine = collapseWhitespace(in: titleLine)
        guard !normalizedLine.isEmpty else {
            return (title: "Unknown Title", author: "Unknown Author")
        }

        let separator = " -- "
        let finalParenthesized = finalParenthesizedGroup(in: normalizedLine)
        var cleanedTitle = normalizedLine
        var fallbackAuthor: String?

        if let firstSeparatorRange = normalizedLine.range(of: separator) {
            cleanedTitle = String(normalizedLine[..<firstSeparatorRange.lowerBound])
            let remainder = normalizedLine[firstSeparatorRange.upperBound...]
            if let secondSeparatorRange = remainder.range(of: separator) {
                fallbackAuthor = String(remainder[..<secondSeparatorRange.lowerBound])
            } else {
                fallbackAuthor = String(remainder)
            }
        } else if let finalParenthesized {
            let titlePrefix = normalizedLine[..<finalParenthesized.range.lowerBound]
            cleanedTitle = String(titlePrefix)
        }

        cleanedTitle = collapseWhitespace(in: cleanedTitle)
        if cleanedTitle.isEmpty {
            cleanedTitle = "Unknown Title"
        }

        let parsedAuthor = finalParenthesized?.value ?? fallbackAuthor ?? "Unknown Author"
        let cleanedAuthor = collapseWhitespace(in: parsedAuthor)
        if cleanedAuthor.isEmpty {
            return (title: cleanedTitle, author: "Unknown Author")
        }

        return (title: cleanedTitle, author: cleanedAuthor)
    }

    static func parseKindleDate(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let date = kindleDateFormatter.date(from: trimmed) else {
            parseErrorCount += 1
            return nil
        }
        return date
    }

    static func computeDedupeKey(bookId: UUID, location: String?, quoteText: String) -> String {
        DedupeKeyBuilder.makeKey(bookId: bookId, location: location, quoteText: quoteText)
    }

    static func resetParseErrorCount() {
        parseErrorCount = 0
    }

    static func parseClippings(fileURL: URL) -> (highlights: [Highlight], books: [Book], parseErrorCount: Int) {
        resetParseErrorCount()

        guard let rawContents = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return (highlights: [], books: [], parseErrorCount: parseErrorCount)
        }

        let chunks = splitRawEntries(rawContents)
        let extractedChunks = extractEntryFields(from: chunks)

        var booksByKey: [ParsedBookKey: ParsedBookRecord] = [:]
        var bookOrder: [ParsedBookKey] = []
        var highlights: [Highlight] = []
        var seenDedupeKeys = Set<String>()

        for extractedChunk in extractedChunks {
            let cleanedBook = cleanTitleAndAuthor(from: extractedChunk.titleLine)
            let bookKey = ParsedBookKey(title: cleanedBook.title, author: cleanedBook.author)

            if booksByKey[bookKey] == nil {
                booksByKey[bookKey] = ParsedBookRecord(id: UUID(), highlightCount: 0)
                bookOrder.append(bookKey)
            }

            guard let bookRecord = booksByKey[bookKey] else {
                continue
            }

            let metadataFields = parseMetadataFields(from: extractedChunk.metadataLine)
            let dedupeKey = computeDedupeKey(
                bookId: bookRecord.id,
                location: metadataFields.location,
                quoteText: extractedChunk.quoteBody
            )

            guard seenDedupeKeys.insert(dedupeKey).inserted else {
                continue
            }

            booksByKey[bookKey]?.highlightCount += 1
            highlights.append(
                Highlight(
                    id: UUID(),
                    bookId: bookRecord.id,
                    quoteText: extractedChunk.quoteBody,
                    bookTitle: cleanedBook.title,
                    author: cleanedBook.author,
                    location: metadataFields.location,
                    dateAdded: metadataFields.dateAdded,
                    lastShownAt: nil
                )
            )
        }

        let books = bookOrder.compactMap { bookKey -> Book? in
            guard let bookRecord = booksByKey[bookKey] else {
                return nil
            }

            return Book(
                id: bookRecord.id,
                title: bookKey.title,
                author: bookKey.author,
                isEnabled: true,
                highlightCount: bookRecord.highlightCount
            )
        }

        return (highlights: highlights, books: books, parseErrorCount: parseErrorCount)
    }

    private static func extractEntryFields(from chunk: String) -> ExtractedChunk? {
        let lines = chunk
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let titleIndex = lines.firstIndex(where: { !isBlankLine($0) }) else {
            return nil
        }
        let titleLine = lines[titleIndex].trimmingCharacters(in: .whitespacesAndNewlines)

        guard titleIndex < lines.count - 1 else {
            return nil
        }
        guard let metadataIndex = lines[(titleIndex + 1)...].firstIndex(where: { $0.hasPrefix("- Your ") }) else {
            return nil
        }
        let metadataLine = lines[metadataIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard metadataLine.contains("Your Highlight") else {
            return nil
        }

        guard metadataIndex < lines.count - 1 else {
            return nil
        }
        guard let blankLineIndex = lines[(metadataIndex + 1)...].firstIndex(where: isBlankLine) else {
            return nil
        }

        let quoteStartIndex = blankLineIndex + 1
        guard quoteStartIndex < lines.count else {
            return nil
        }

        let quoteBody = lines[quoteStartIndex...]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quoteBody.isEmpty else {
            return nil
        }

        return ExtractedChunk(
            titleLine: titleLine,
            metadataLine: metadataLine,
            quoteBody: quoteBody
        )
    }

    private static func appendChunk(from lines: [Substring], into chunks: inout [String]) {
        let chunk = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else {
            return
        }
        chunks.append(chunk)
    }

    private static func isBlankLine(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func collapseWhitespace(in string: String) -> String {
        string.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func finalParenthesizedGroup(in line: String) -> (value: String, range: Range<String.Index>)? {
        guard
            let closingParen = line.lastIndex(of: ")"),
            closingParen == line.index(before: line.endIndex),
            let openingParen = line[..<closingParen].lastIndex(of: "(")
        else {
            return nil
        }

        let contentRange = line.index(after: openingParen)..<closingParen
        let content = collapseWhitespace(in: String(line[contentRange]))
        guard !content.isEmpty else {
            return nil
        }

        let fullRange = openingParen..<line.index(after: closingParen)
        return (value: content, range: fullRange)
    }

    private static func parseMetadataFields(from metadataLine: String) -> (location: String?, dateAdded: Date?) {
        let segments = metadataLine.split(separator: "|", omittingEmptySubsequences: false).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        var location: String?
        var dateAdded: Date?

        for segment in segments {
            if segment.hasPrefix("Location ") {
                let rawLocation = String(segment.dropFirst("Location ".count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawLocation.isEmpty {
                    location = rawLocation
                }
                continue
            }

            if let addedOnRange = segment.range(of: "Added on ") {
                let rawDate = String(segment[addedOnRange.upperBound...])
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !rawDate.isEmpty {
                    dateAdded = parseKindleDate(rawDate)
                }
            }
        }

        return (location: location, dateAdded: dateAdded)
    }
}
