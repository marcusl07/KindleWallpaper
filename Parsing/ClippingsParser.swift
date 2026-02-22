import Foundation

enum ClippingsParser {
    private static let separator = "=========="

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

    private static func appendChunk(from lines: [Substring], into chunks: inout [String]) {
        let chunk = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !chunk.isEmpty else {
            return
        }
        chunks.append(chunk)
    }
}
