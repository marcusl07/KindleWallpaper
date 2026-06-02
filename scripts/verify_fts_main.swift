import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_fts_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fail("\(message). Expected \(expected), got \(actual)")
    }
}

// Mirror the implementation to verify string processing logic
func normalizedFTSSearchQuery(for rawValue: String) -> String? {
    let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmedValue.isEmpty else {
        return nil
    }
    
    let words = trimmedValue.components(separatedBy: .whitespacesAndNewlines)
        .map { $0.replacingOccurrences(of: "\"", with: "") }
        .filter { !$0.isEmpty }
        
    guard !words.isEmpty else {
        return nil
    }
    
    let queryParts = words.map { "\"\($0)\"*" }
    return queryParts.joined(separator: " AND ")
}

func testQueryNormalization() {
    // Empty queries
    assertEqual(normalizedFTSSearchQuery(for: ""), nil, "Empty string should return nil")
    assertEqual(normalizedFTSSearchQuery(for: "   \n  "), nil, "Whitespace-only string should return nil")
    
    // Single word
    assertEqual(normalizedFTSSearchQuery(for: "test"), "\"test\"*", "Single word query formatting")
    assertEqual(normalizedFTSSearchQuery(for: "  test  "), "\"test\"*", "Trimmed single word query formatting")
    
    // Multiple words
    assertEqual(normalizedFTSSearchQuery(for: "hello world"), "\"hello\"* AND \"world\"*", "Multi-word query formatting")
    assertEqual(normalizedFTSSearchQuery(for: "  hello   world  "), "\"hello\"* AND \"world\"*", "Multi-word query formatting with extra whitespace")
    
    // Characters escaping (specifically double quotes)
    assertEqual(normalizedFTSSearchQuery(for: "hello \"world\""), "\"hello\"* AND \"world\"*", "Strip double quotes from queries")
}

testQueryNormalization()
print("verify_fts_main Swift tests passed successfully!")
