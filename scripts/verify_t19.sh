#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t19.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/verify_t19.swift" <<'SWIFT'
import Foundation

@main
struct VerifyT19 {
    static func main() throws {
        try testFindsCaseInsensitiveFilenameViaFallbackSearch()
        try testPrefersDocumentsPathFoundDuringFallbackScan()
        try testReturnsFirstNonDocumentsMatchWhenNoDocumentsMatchExists()
        try testSkipsHiddenSystemAndAppDirectories()
        try testDepthLimitPreventsDeepMatch()
        try testDirectoryVisitCapStopsSearch()
        try testTimeLimitStopsSearch()
        print("T19 verification passed")
    }

    private static func testFindsCaseInsensitiveFilenameViaFallbackSearch() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let fallbackMatch = fixture.volumeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Subfolder", isDirectory: true)
            .appendingPathComponent("my clippings.TXT", isDirectory: false)
        try fixture.createFile(at: fallbackMatch)

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqualURL(result, fallbackMatch, "Expected case-insensitive clippings filename match in fallback search")
    }

    private static func testPrefersDocumentsPathFoundDuringFallbackScan() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let nonDocumentsMatch = fixture.volumeURL
            .appendingPathComponent("a_non_documents", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)
        let documentsMatch = fixture.volumeURL
            .appendingPathComponent("z_parent", isDirectory: true)
            .appendingPathComponent("documents", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)

        try fixture.createFile(at: nonDocumentsMatch)
        try fixture.createFile(at: documentsMatch)

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqualURL(result, documentsMatch, "Expected documents-path match to override earlier non-documents match")
    }

    private static func testReturnsFirstNonDocumentsMatchWhenNoDocumentsMatchExists() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let firstMatch = fixture.volumeURL
            .appendingPathComponent("a_first", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)
        let secondMatch = fixture.volumeURL
            .appendingPathComponent("z_second", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)

        try fixture.createFile(at: firstMatch)
        try fixture.createFile(at: secondMatch)

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqualURL(result, firstMatch, "Expected first fallback match to be returned when no documents-path match exists")
    }

    private static func testSkipsHiddenSystemAndAppDirectories() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let hiddenMatch = fixture.volumeURL
            .appendingPathComponent(".hidden", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)
        let spotlightMatch = fixture.volumeURL
            .appendingPathComponent(".Spotlight-V100", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)
        let appPackageMatch = fixture.volumeURL
            .appendingPathComponent("Reader.app", isDirectory: true)
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)
        let visibleMatch = fixture.volumeURL
            .appendingPathComponent("visible", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)

        try fixture.createFile(at: hiddenMatch)
        try fixture.createFile(at: spotlightMatch)
        try fixture.createFile(at: appPackageMatch)
        try fixture.createFile(at: visibleMatch)

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqualURL(result, visibleMatch, "Expected scanner to skip hidden/system/.app directories and return visible match")
    }

    private static func testDepthLimitPreventsDeepMatch() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let tooDeepMatch = fixture.volumeURL
            .appendingPathComponent("a", isDirectory: true)
            .appendingPathComponent("b", isDirectory: true)
            .appendingPathComponent("c", isDirectory: true)
            .appendingPathComponent("d", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)
        try fixture.createFile(at: tooDeepMatch)

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqual(result, nil, "Expected depth > 3 matches to be ignored")
    }

    private static func testDirectoryVisitCapStopsSearch() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        for index in 1...2001 {
            let directoryName = String(format: "d%04d", index)
            let directoryURL = fixture.volumeURL.appendingPathComponent(directoryName, isDirectory: true)
            try fixture.fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

            if index == 2001 {
                let cappedMatch = directoryURL.appendingPathComponent("My Clippings.txt", isDirectory: false)
                try fixture.createFile(at: cappedMatch)
            }
        }

        let result = VolumeWatcher.findClippingsFile(on: fixture.volumeURL, fileManager: fixture.fileManager)
        assertEqual(result, nil, "Expected scan to stop before visiting more than 2000 directories")
    }

    private static func testTimeLimitStopsSearch() throws {
        let fixture = try Fixture.make()
        defer { fixture.cleanup() }

        let fallbackMatch = fixture.volumeURL
            .appendingPathComponent("slow", isDirectory: true)
            .appendingPathComponent("My Clippings.txt", isDirectory: false)
        try fixture.createFile(at: fallbackMatch)

        let start = Date()
        var callCount = 0
        let result = VolumeWatcher.findClippingsFile(
            on: fixture.volumeURL,
            fileManager: fixture.fileManager,
            now: {
                defer { callCount += 1 }
                return callCount == 0 ? start : start.addingTimeInterval(2)
            }
        )

        assertEqual(result, nil, "Expected search to stop once elapsed time exceeds one second")
    }

    private static func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
        if actual != expected {
            fputs("Assertion failed: \(message). Expected \(String(describing: expected)), got \(String(describing: actual))\n", stderr)
            exit(1)
        }
    }

    private static func assertEqualURL(_ actual: URL?, _ expected: URL?, _ message: String) {
        let actualPath = actual?.resolvingSymlinksInPath().standardizedFileURL.path
        let expectedPath = expected?.resolvingSymlinksInPath().standardizedFileURL.path
        if actualPath != expectedPath {
            fputs("Assertion failed: \(message). Expected \(String(describing: expectedPath)), got \(String(describing: actualPath))\n", stderr)
            exit(1)
        }
    }
}

private struct Fixture {
    let rootURL: URL
    let volumeURL: URL
    let fileManager: FileManager

    static func make() throws -> Fixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent("kindlewall-t19-\(UUID().uuidString)", isDirectory: true)
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
  "$TMP_DIR/verify_t19.swift" \
  -o "$TMP_DIR/t19_runner"

"$TMP_DIR/t19_runner"
