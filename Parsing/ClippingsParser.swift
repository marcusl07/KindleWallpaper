import Foundation

enum ClippingsParser {
    private static let separator = "=========="

    struct ExtractedChunk: Equatable {
        let titleLine: String
        let metadataLine: String
        let quoteBody: String
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
}
