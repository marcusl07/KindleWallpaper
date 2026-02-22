#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t18.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/verify_t18.swift" <<'SWIFT'
import Foundation

@main
struct VerifyT18 {
    static func main() throws {
        try testReturnsLowercaseDocumentsPathFirst()
        try testPrefersDocumentsPathOverRootPath()
        try testReturnsRootPathWhenDocumentsPathsMissing()
        try testReturnsNilWhenKnownPathsMissing()
        try testSkipsDirectoryMatches()
        print("T18 verification passed")
    }

    private static func testReturnsLowercaseDocumentsPathFirst() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let lowercase = fixture.volumeURL.appendingPathComponent("documents/My Clippings.txt", isDirectory: false)
        let capitalized = fixture.volumeURL.appendingPathComponent("Documents/My Clippings.txt", isDirectory: false)
        let root = fixture.volumeURL.appendingPathComponent("My Clippings.txt", isDirectory: false)

        try fixture.createFile(at: lowercase)
        try fixture.createFile(at: capitalized)
        try fixture.createFile(at: root)

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqual(result, lowercase, "Expected lowercase documents path to win by order")
    }

    private static func testPrefersDocumentsPathOverRootPath() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let capitalized = fixture.volumeURL.appendingPathComponent("Documents/My Clippings.txt", isDirectory: false)
        let root = fixture.volumeURL.appendingPathComponent("My Clippings.txt", isDirectory: false)
        try fixture.createFile(at: capitalized)
        try fixture.createFile(at: root)

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        guard let result else {
            fail("Expected a documents-path match when documents and root files both exist")
        }

        assertNotEqual(result, root, "Expected documents variant to be preferred over root path")
        assertEqual(
            result.deletingLastPathComponent().lastPathComponent.lowercased(),
            "documents",
            "Expected match under a documents directory"
        )
    }

    private static func testReturnsRootPathWhenDocumentsPathsMissing() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let root = fixture.volumeURL.appendingPathComponent("My Clippings.txt", isDirectory: false)
        try fixture.createFile(at: root)

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqual(result, root, "Expected root clipping file when documents variants are absent")
    }

    private static func testReturnsNilWhenKnownPathsMissing() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqual(result, nil, "Expected nil when no known clippings paths exist")
    }

    private static func testSkipsDirectoryMatches() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let lowercaseDirectory = fixture.volumeURL.appendingPathComponent("documents/My Clippings.txt", isDirectory: true)
        try fixture.fileManager.createDirectory(at: lowercaseDirectory, withIntermediateDirectories: true)

        let fallback = fixture.volumeURL.appendingPathComponent("My Clippings.txt", isDirectory: false)
        try fixture.createFile(at: fallback)

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqual(result, fallback, "Expected directories to be ignored and next file match returned")
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            fputs("Assertion failed: \(message). Expected \(String(describing: expected)), got \(String(describing: actual))\n", stderr)
            exit(1)
        }
    }

    private static func assertNotEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual == expected {
            fputs("Assertion failed: \(message). Value: \(String(describing: actual))\n", stderr)
            exit(1)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("Assertion failed: \(message)\n", stderr)
        exit(1)
    }
}

private struct Fixture {
    let rootURL: URL
    let volumeURL: URL
    let fileManager: FileManager

    static func make() throws -> Fixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent("kindlewall-t18-\(UUID().uuidString)", isDirectory: true)
        let volumeURL = rootURL.appendingPathComponent("Kindle", isDirectory: true)
        try fileManager.createDirectory(at: volumeURL, withIntermediateDirectories: true)
        return Fixture(rootURL: rootURL, volumeURL: volumeURL, fileManager: fileManager)
    }

    func createFile(at url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("sample".utf8).write(to: url)
    }

    func cleanup() {
        try? fileManager.removeItem(at: rootURL)
    }
}
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/VolumeWatcher.swift" \
  "$TMP_DIR/verify_t18.swift" \
  -o "$TMP_DIR/t18_runner"

"$TMP_DIR/t18_runner"
