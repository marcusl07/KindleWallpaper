#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/verify_t21.swift" <<'SWIFT'
import Foundation
import Darwin

@main
struct VerifyT21 {
    static func main() throws {
        try testSaveAndLoadBackgroundImage()
        try testLoadReturnsNilWhenUnset()
        try testSaveThrowsWhenSourceMissing()
        try testLoadClearsMissingPath()
        try testSecondSaveReplacesPreviousBackgroundFile()
        print("T21 verification passed")
    }

    private static func testSaveAndLoadBackgroundImage() throws {
        let fixture = try TestFixture.make()
        defer { fixture.cleanup() }

        let sourceURL = fixture.rootURL.appendingPathComponent("selected.jpg")
        try Data("sample-image-data".utf8).write(to: sourceURL)

        let destinationURL = try fixture.store.saveBackgroundImage(from: sourceURL)

        expect(destinationURL.lastPathComponent == "background.jpg", "Expected copied file to preserve extension")
        expect(FileManager.default.fileExists(atPath: destinationURL.path), "Expected copied file to exist")
        let loadedURL = fixture.store.loadBackgroundImageURL()
        expect(loadedURL == destinationURL, "Expected loadBackgroundImageURL to return saved URL")
        let persistedPath = fixture.defaults.string(forKey: fixture.pathKey)
        expect(persistedPath == destinationURL.path, "Expected UserDefaults path to match destination")
    }

    private static func testLoadReturnsNilWhenUnset() throws {
        let fixture = try TestFixture.make()
        defer { fixture.cleanup() }

        expect(fixture.store.loadBackgroundImageURL() == nil, "Expected nil when no background has been saved")
    }

    private static func testSaveThrowsWhenSourceMissing() throws {
        let fixture = try TestFixture.make()
        defer { fixture.cleanup() }

        let missingURL = fixture.rootURL.appendingPathComponent("missing.png")

        do {
            _ = try fixture.store.saveBackgroundImage(from: missingURL)
            fail("Expected save to throw for a missing source file")
        } catch {
            // Expected path.
        }
    }

    private static func testLoadClearsMissingPath() throws {
        let fixture = try TestFixture.make()
        defer { fixture.cleanup() }

        let stalePath = fixture.rootURL.appendingPathComponent("no-longer-there.jpg").path
        fixture.defaults.set(stalePath, forKey: fixture.pathKey)

        expect(fixture.store.loadBackgroundImageURL() == nil, "Expected nil for missing stored file")
        expect(fixture.defaults.object(forKey: fixture.pathKey) == nil, "Expected stale path to be removed from defaults")
    }

    private static func testSecondSaveReplacesPreviousBackgroundFile() throws {
        let fixture = try TestFixture.make()
        defer { fixture.cleanup() }

        let firstSource = fixture.rootURL.appendingPathComponent("first.png")
        let secondSource = fixture.rootURL.appendingPathComponent("second.heic")
        try Data("first".utf8).write(to: firstSource)
        try Data("second".utf8).write(to: secondSource)

        let firstDestination = try fixture.store.saveBackgroundImage(from: firstSource)
        let secondDestination = try fixture.store.saveBackgroundImage(from: secondSource)

        expect(!FileManager.default.fileExists(atPath: firstDestination.path), "Expected previous background file to be removed")
        expect(FileManager.default.fileExists(atPath: secondDestination.path), "Expected newest background file to exist")
        expect(secondDestination.lastPathComponent == "background.heic", "Expected latest extension to be preserved")
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if !condition() {
            fail(message)
        }
    }

    private static func fail(_ message: String) -> Never {
        fputs("Verification failure: \(message)\n", stderr)
        Darwin.exit(1)
    }
}

private struct TestFixture {
    let rootURL: URL
    let appSupportURL: URL
    let defaults: UserDefaults
    let store: BackgroundImageStore
    let defaultsSuiteName: String
    let pathKey = "backgroundImagePath"

    static func make() throws -> TestFixture {
        let fm = FileManager.default
        let rootURL = fm.temporaryDirectory.appendingPathComponent("kindlewall-t21-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let appSupportURL = rootURL.appendingPathComponent("ApplicationSupport/KindleWall", isDirectory: true)
        let suiteName = "verify_t21.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(domain: "VerifyT21", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create UserDefaults suite"])
        }
        defaults.removePersistentDomain(forName: suiteName)

        let store = BackgroundImageStore(
            fileManager: fm,
            userDefaults: defaults,
            appSupportDirectoryURL: appSupportURL
        )

        return TestFixture(
            rootURL: rootURL,
            appSupportURL: appSupportURL,
            defaults: defaults,
            store: store,
            defaultsSuiteName: suiteName
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}
SWIFT

swiftc \
  -module-cache-path "$tmp_dir/module-cache" \
  App/BackgroundImageStore.swift \
  "$tmp_dir/verify_t21.swift" \
  -o "$tmp_dir/verify_t21"

"$tmp_dir/verify_t21"
