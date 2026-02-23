#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d /tmp/kindlewall_h4.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import AppKit
import Darwin
import Foundation

func testMissingFileOutcomeAndDedupedWarning() {
    var warnings: [String] = []
    let loader = BackgroundImageLoader(logger: { warnings.append($0) })
    let missingURL = FileManager.default.temporaryDirectory.appendingPathComponent("kindlewall-h4-missing-\(UUID().uuidString).png")

    let first = loader.load(from: missingURL)
    let second = loader.load(from: missingURL)

    expect(first.image == nil, "Expected missing-file load to return nil image")
    expect(second.image == nil, "Expected repeated missing-file load to return nil image")

    if case .missingFile(let path) = first.outcome {
        expect(path == missingURL.path, "Expected missing-file path to match URL")
    } else {
        fail("Expected missing-file outcome for first load")
    }

    if case .missingFile(let path) = second.outcome {
        expect(path == missingURL.path, "Expected missing-file path to match URL on repeated load")
    } else {
        fail("Expected missing-file outcome for second load")
    }

    expect(warnings.count == 1, "Expected one deduped warning for repeated missing-file loads")
}

func testUnreadableOutcomeAndDedupedWarning() throws {
    let fixture = try TestFixture.make()
    defer { fixture.cleanup() }

    let unreadableURL = fixture.rootURL.appendingPathComponent("unreadable.png")
    try writePNG(at: unreadableURL, width: 12, height: 12, color: .red)

    var warnings: [String] = []
    let loader = BackgroundImageLoader(logger: { warnings.append($0) })

    let originalPermissions = try filePermissions(atPath: unreadableURL.path)
    guard chmod(unreadableURL.path, 0) == 0 else {
        fail("Failed to set unreadable permissions for test file")
    }

    defer {
        _ = chmod(unreadableURL.path, mode_t(originalPermissions))
    }

    let first = loader.load(from: unreadableURL)
    let second = loader.load(from: unreadableURL)

    expect(first.image == nil, "Expected unreadable-file load to return nil image")
    expect(second.image == nil, "Expected repeated unreadable-file load to return nil image")

    if case .unreadableFile(let path) = first.outcome {
        expect(path == unreadableURL.path, "Expected unreadable-file path to match URL")
    } else {
        fail("Expected unreadable-file outcome for first load")
    }

    if case .unreadableFile(let path) = second.outcome {
        expect(path == unreadableURL.path, "Expected unreadable-file path to match URL on repeated load")
    } else {
        fail("Expected unreadable-file outcome for second load")
    }

    expect(warnings.count == 1, "Expected one deduped warning for repeated unreadable-file loads")
}

func testDecodeFailureOutcomeAndDedupedWarning() throws {
    let fixture = try TestFixture.make()
    defer { fixture.cleanup() }

    let badDataURL = fixture.rootURL.appendingPathComponent("invalid-image.png")
    try Data("this is not a png".utf8).write(to: badDataURL)

    var warnings: [String] = []
    let loader = BackgroundImageLoader(logger: { warnings.append($0) })

    let first = loader.load(from: badDataURL)
    let second = loader.load(from: badDataURL)

    expect(first.image == nil, "Expected decode-failure load to return nil image")
    expect(second.image == nil, "Expected repeated decode-failure load to return nil image")

    if case .decodeFailed(let path) = first.outcome {
        expect(path == badDataURL.path, "Expected decode-failure path to match URL")
    } else {
        fail("Expected decode-failure outcome for first load")
    }

    if case .decodeFailed(let path) = second.outcome {
        expect(path == badDataURL.path, "Expected decode-failure path to match URL on repeated load")
    } else {
        fail("Expected decode-failure outcome for second load")
    }

    expect(warnings.count == 1, "Expected one deduped warning for repeated decode-failure loads")
}

func testSuccessCachingAndInvalidationOnFileChange() throws {
    let fixture = try TestFixture.make()
    defer { fixture.cleanup() }

    let imageURL = fixture.rootURL.appendingPathComponent("background.png")
    try writePNG(at: imageURL, width: 16, height: 16, color: .blue)

    var decodeCount = 0
    let loader = BackgroundImageLoader(
        loadImage: { url in
            decodeCount += 1
            return NSImage(contentsOf: url)
        },
        logger: { _ in }
    )

    let first = loader.load(from: imageURL)
    let second = loader.load(from: imageURL)

    expect(first.image != nil, "Expected first successful decode to produce image")
    expect(second.image != nil, "Expected cached decode to produce image")
    expect(decodeCount == 1, "Expected second load to hit cache without re-decoding")

    try writePNG(at: imageURL, width: 32, height: 32, color: .green)
    try FileManager.default.setAttributes(
        [.modificationDate: Date().addingTimeInterval(5)],
        ofItemAtPath: imageURL.path
    )

    let third = loader.load(from: imageURL)

    expect(third.image != nil, "Expected post-mutation load to produce image")
    expect(decodeCount == 2, "Expected cache invalidation when file identity changes")
}

func testWallpaperGeneratorFallsBackWhenBackgroundDecodeFails() throws {
    let fixture = try TestFixture.make()
    defer { fixture.cleanup() }

    let badDataURL = fixture.rootURL.appendingPathComponent("bad-background.png")
    try Data("not-an-image".utf8).write(to: badDataURL)

    let loader = BackgroundImageLoader(logger: { _ in })
    let generator = WallpaperGenerator(
        fileManager: .default,
        appSupportDirectoryProvider: { fixture.appSupportURL },
        mainScreenPixelSizeProvider: { CGSize(width: 1920, height: 1080) },
        backgroundImageLoader: loader,
        retainedGeneratedFileCount: 5
    )

    let outputs = generator.generateWallpapers(
        highlight: sampleHighlight(),
        backgroundURL: badDataURL,
        targets: [WallpaperGenerator.RenderTarget(identifier: "display-1", pixelWidth: 640, pixelHeight: 360)],
        rotationID: "h4-fallback"
    )

    expect(outputs.count == 1, "Expected one generated wallpaper for fallback verification")
    let outputURL = outputs[0].fileURL
    expect(FileManager.default.fileExists(atPath: outputURL.path), "Expected fallback-generated wallpaper file to exist")

    let dimensions = try imageDimensions(at: outputURL)
    expect(dimensions.width == 640 && dimensions.height == 360, "Expected fallback wallpaper dimensions to match target")
}

func sampleHighlight() -> Highlight {
    Highlight(
        id: UUID(),
        bookId: UUID(),
        quoteText: "Fallback path verification quote.",
        bookTitle: "Book",
        author: "Author",
        location: "1-2",
        dateAdded: nil,
        lastShownAt: nil
    )
}

func imageDimensions(at url: URL) throws -> (width: Int, height: Int) {
    let data = try Data(contentsOf: url)
    guard let bitmap = NSBitmapImageRep(data: data) else {
        throw NSError(domain: "VerifyH4", code: 4, userInfo: [NSLocalizedDescriptionKey: "Failed to decode output image"]) 
    }
    return (bitmap.pixelsWide, bitmap.pixelsHigh)
}

func writePNG(at url: URL, width: Int, height: Int, color: NSColor) throws {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else {
        throw NSError(domain: "VerifyH4", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate bitmap context"]) 
    }

    let rect = NSRect(x: 0, y: 0, width: width, height: height)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    color.setFill()
    rect.fill()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let pngData = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VerifyH4", code: 6, userInfo: [NSLocalizedDescriptionKey: "Failed to encode png"]) 
    }

    try pngData.write(to: url, options: .atomic)
}

func filePermissions(atPath path: String) throws -> mode_t {
    let attributes = try FileManager.default.attributesOfItem(atPath: path)
    guard let permissions = attributes[.posixPermissions] as? NSNumber else {
        throw NSError(domain: "VerifyH4", code: 7, userInfo: [NSLocalizedDescriptionKey: "Missing file permissions"]) 
    }
    return mode_t(permissions.uint16Value)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

func fail(_ message: String) -> Never {
    fputs("Verification failure: \(message)\n", stderr)
    exit(1)
}

struct TestFixture {
    let rootURL: URL
    let appSupportURL: URL

    static func make() throws -> TestFixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent("kindlewall-h4-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let appSupportURL = rootURL.appendingPathComponent("ApplicationSupport/KindleWall", isDirectory: true)

        return TestFixture(rootURL: rootURL, appSupportURL: appSupportURL)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

do {
    testMissingFileOutcomeAndDedupedWarning()
    try testUnreadableOutcomeAndDedupedWarning()
    try testDecodeFailureOutcomeAndDedupedWarning()
    try testSuccessCachingAndInvalidationOnFileChange()
    try testWallpaperGeneratorFallsBackWhenBackgroundDecodeFails()
    print("H4 verification passed")
} catch {
    fputs("Verification failure: \(error)\n", stderr)
    exit(1)
}
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  App/AppSupportPaths.swift \
  App/BackgroundImageStore.swift \
  App/WallpaperGenerator.swift \
  Models/Highlight.swift \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/h4_runner"

"$TMP_DIR/h4_runner"
