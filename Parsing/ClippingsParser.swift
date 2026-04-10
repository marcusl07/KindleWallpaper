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

    struct ParseResult {
        let highlights: [Highlight]
        let books: [Book]
        let parseErrorCount: Int
        let skippedEntryCount: Int
        let warningMessages: [String]
        let error: String?
    }

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

    private enum ChunkClassification: Equatable {
        case highlight(ExtractedChunk)
        case ignored
        case malformed(snippet: String)
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
        return kindleDateFormatter.date(from: trimmed)
    }

    static func computeDedupeKey(bookId: UUID, location: String?, quoteText: String) -> String {
        DedupeKeyBuilder.makeKey(bookId: bookId, location: location, quoteText: quoteText)
    }

    static func parseClippings(fileURL: URL) -> ParseResult {
        let fileData: Data

        do {
            fileData = try Data(contentsOf: fileURL)
        } catch {
            return ParseResult(
                highlights: [],
                books: [],
                parseErrorCount: 0,
                skippedEntryCount: 0,
                warningMessages: [],
                error: readFailureMessage(for: error)
            )
        }

        guard let rawContents = String(data: fileData, encoding: .utf8) else {
            return ParseResult(
                highlights: [],
                books: [],
                parseErrorCount: 0,
                skippedEntryCount: 0,
                warningMessages: [],
                error: "clippings file uses an unsupported text encoding. Use a UTF-8 text file and try again."
            )
        }

        var parseErrorCount = 0
        var warningMessages: [String] = []
        let chunks = splitRawEntries(rawContents)
        let classifications = chunks.map(classifyChunk)
        var extractedChunks: [ExtractedChunk] = []
        extractedChunks.reserveCapacity(classifications.count)
        let skippedEntryCount = classifications.reduce(into: 0) { count, classification in
            switch classification {
            case let .highlight(chunk):
                extractedChunks.append(chunk)
            case .ignored:
                break
            case let .malformed(snippet):
                count += 1
                warningMessages.append("Skipped malformed entry near: \"\(snippet)\"")
            }
        }

        if extractedChunks.isEmpty {
            return ParseResult(
                highlights: [],
                books: [],
                parseErrorCount: 0,
                skippedEntryCount: skippedEntryCount,
                warningMessages: warningMessages,
                error: "clippings file does not contain any valid Kindle highlight entries."
            )
        }

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

            let metadataFields = parseMetadataFields(
                from: extractedChunk.metadataLine,
                entrySnippet: warningSnippet(from: "\(extractedChunk.titleLine) \(extractedChunk.metadataLine)"),
                parseErrorCount: &parseErrorCount,
                warningMessages: &warningMessages
            )
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

        return ParseResult(
            highlights: highlights,
            books: books,
            parseErrorCount: parseErrorCount,
            skippedEntryCount: skippedEntryCount,
            warningMessages: warningMessages,
            error: nil
        )
    }

    private static func extractEntryFields(from chunk: String) -> ExtractedChunk? {
        guard case let .highlight(extractedChunk) = classifyChunk(chunk) else {
            return nil
        }

        return extractedChunk
    }

    private static func classifyChunk(_ chunk: String) -> ChunkClassification {
        let lines = chunk
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        guard let titleIndex = lines.firstIndex(where: { !isBlankLine($0) }) else {
            return malformedClassification(for: chunk)
        }
        let titleLine = lines[titleIndex].trimmingCharacters(in: .whitespacesAndNewlines)

        guard titleIndex < lines.count - 1 else {
            return malformedClassification(for: chunk)
        }
        guard let metadataIndex = lines[(titleIndex + 1)...].firstIndex(where: { $0.hasPrefix("- Your ") }) else {
            return malformedClassification(for: chunk)
        }
        let metadataLine = lines[metadataIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard metadataLine.contains("Your Highlight") else {
            return .ignored
        }

        guard metadataIndex < lines.count - 1 else {
            return malformedClassification(for: chunk)
        }
        guard let blankLineIndex = lines[(metadataIndex + 1)...].firstIndex(where: isBlankLine) else {
            return malformedClassification(for: chunk)
        }

        let quoteStartIndex = blankLineIndex + 1
        guard quoteStartIndex < lines.count else {
            return malformedClassification(for: chunk)
        }

        let quoteBody = lines[quoteStartIndex...]
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quoteBody.isEmpty else {
            return malformedClassification(for: chunk)
        }

        return .highlight(ExtractedChunk(
            titleLine: titleLine,
            metadataLine: metadataLine,
            quoteBody: quoteBody
        ))
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

    private static func parseMetadataFields(
        from metadataLine: String,
        entrySnippet: String,
        parseErrorCount: inout Int,
        warningMessages: inout [String]
    ) -> (location: String?, dateAdded: Date?) {
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
                    dateAdded = parseKindleDate(
                        rawDate,
                        entrySnippet: entrySnippet,
                        parseErrorCount: &parseErrorCount,
                        warningMessages: &warningMessages
                    )
                }
            }
        }

        return (location: location, dateAdded: dateAdded)
    }

    private static func parseKindleDate(
        _ string: String,
        entrySnippet: String,
        parseErrorCount: inout Int,
        warningMessages: inout [String]
    ) -> Date? {
        guard let date = parseKindleDate(string) else {
            parseErrorCount += 1
            warningMessages.append("Could not parse Added on date in entry: \"\(entrySnippet)\"")
            return nil
        }
        return date
    }

    private static func malformedClassification(for chunk: String) -> ChunkClassification {
        .malformed(snippet: warningSnippet(from: chunk))
    }

    private static func warningSnippet(from text: String, maximumLength: Int = 80) -> String {
        let collapsed = collapseWhitespace(in: text).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else {
            return "entry text unavailable"
        }

        guard collapsed.count > maximumLength else {
            return collapsed
        }

        let cutoffIndex = collapsed.index(collapsed.startIndex, offsetBy: maximumLength - 3)
        return "\(collapsed[..<cutoffIndex])..."
    }

    private static func readFailureMessage(for error: Error) -> String {
        let description = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !description.isEmpty else {
            return "could not read clippings file."
        }
        return "could not read clippings file (\(description))."
    }
}
