#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d /tmp/kindlewall_t22.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import AppKit
import Foundation

func testGenerateWithoutBackgroundCreatesExpectedPNG() throws {
    let fixture = try TestFixture.make(screenSize: CGSize(width: 1200, height: 800))
    defer { fixture.cleanup() }

    let outputURL = fixture.generator.generateWallpaper(
        highlight: sampleHighlight(quote: "A short quote for baseline coverage."),
        backgroundURL: nil
    )

    let expectedURL = fixture.appSupportURL.appendingPathComponent("current_wallpaper.png", isDirectory: false)
    expect(outputURL == expectedURL, "Expected wallpaper to be written to current_wallpaper.png in app support")
    expect(FileManager.default.fileExists(atPath: outputURL.path), "Expected output file to exist")

    let dimensions = try imageDimensions(at: outputURL)
    expect(dimensions.width == 1200 && dimensions.height == 800, "Expected output dimensions to match provided screen size")
}

func testMissingBackgroundFallsBackToBlackCanvas() throws {
    let fixture = try TestFixture.make(screenSize: CGSize(width: 1440, height: 900))
    defer { fixture.cleanup() }

    let missingBackgroundURL = fixture.rootURL.appendingPathComponent("does-not-exist.jpg", isDirectory: false)
    let outputURL = fixture.generator.generateWallpaper(
        highlight: sampleHighlight(quote: "Fallback behavior should still produce a wallpaper."),
        backgroundURL: missingBackgroundURL
    )

    expect(FileManager.default.fileExists(atPath: outputURL.path), "Expected output file to exist when background image is missing")
    let dimensions = try imageDimensions(at: outputURL)
    expect(dimensions.width == 1440 && dimensions.height == 900, "Expected fallback output dimensions to match provided screen size")
}

func testGenerationNormalizesOutputToTargetScreenSize() throws {
    let fixture = try TestFixture.make(screenSize: CGSize(width: 1000, height: 500))
    defer { fixture.cleanup() }

    let backgroundURL = fixture.rootURL.appendingPathComponent("large-background.png", isDirectory: false)
    try writeSolidPNG(color: .systemBlue, size: CGSize(width: 4000, height: 2200), to: backgroundURL)

    let outputURL = fixture.generator.generateWallpaper(
        highlight: sampleHighlight(quote: "This quote verifies source-image scaling behavior."),
        backgroundURL: backgroundURL
    )

    let dimensions = try imageDimensions(at: outputURL)
    expect(dimensions.width == 1000 && dimensions.height == 500, "Expected output dimensions to be normalized to target screen size")
}

func testNilScreenSizeUsesDeterministicDefault() throws {
    let fixture = try TestFixture.make(screenSize: nil)
    defer { fixture.cleanup() }

    let outputURL = fixture.generator.generateWallpaper(
        highlight: sampleHighlight(quote: "Default sizing should be deterministic for tests."),
        backgroundURL: nil
    )

    let dimensions = try imageDimensions(at: outputURL)
    expect(dimensions.width == 1920 && dimensions.height == 1080, "Expected default output dimensions to be 1920x1080 when screen size is unavailable")
}

func sampleHighlight(quote: String) -> Highlight {
    Highlight(
        id: UUID(),
        bookId: UUID(),
        quoteText: quote,
        bookTitle: "Test Book",
        author: "Test Author",
        location: "123-124",
        dateAdded: nil,
        lastShownAt: nil
    )
}

func writeSolidPNG(color: NSColor, size: CGSize, to url: URL) throws {
    let width = max(Int(size.width.rounded(.toNearestOrAwayFromZero)), 1)
    let height = max(Int(size.height.rounded(.toNearestOrAwayFromZero)), 1)

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
        throw NSError(domain: "VerifyT22", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to allocate bitmap context"])
    }

    let rect = NSRect(origin: .zero, size: CGSize(width: CGFloat(width), height: CGFloat(height)))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    color.setFill()
    rect.fill()
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "VerifyT22", code: 2, userInfo: [NSLocalizedDescriptionKey: "Failed to encode PNG"])
    }

    try data.write(to: url, options: .atomic)
}

func imageDimensions(at url: URL) throws -> (width: Int, height: Int) {
    guard
        let data = try? Data(contentsOf: url),
        let bitmap = NSBitmapImageRep(data: data)
    else {
        throw NSError(domain: "VerifyT22", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode generated PNG"])
    }

    return (bitmap.pixelsWide, bitmap.pixelsHigh)
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Verification failure: \(message)\n", stderr)
        exit(1)
    }
}

struct TestFixture {
    let rootURL: URL
    let appSupportURL: URL
    let generator: WallpaperGenerator

    static func make(screenSize: CGSize?) throws -> TestFixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent("kindlewall-t22-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let appSupportURL = rootURL.appendingPathComponent("ApplicationSupport/KindleWall", isDirectory: true)
        let generator = WallpaperGenerator(
            fileManager: fileManager,
            appSupportDirectoryProvider: { appSupportURL },
            mainScreenPixelSizeProvider: { screenSize }
        )

        return TestFixture(
            rootURL: rootURL,
            appSupportURL: appSupportURL,
            generator: generator
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: rootURL)
    }
}

do {
    try testGenerateWithoutBackgroundCreatesExpectedPNG()
    try testMissingBackgroundFallsBackToBlackCanvas()
    try testGenerationNormalizesOutputToTargetScreenSize()
    try testNilScreenSizeUsesDeterministicDefault()
    print("T22 verification passed")
} catch {
    fputs("Verification failure: \(error)\n", stderr)
    exit(1)
}
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  App/AppSupportPaths.swift \
  App/WallpaperGenerator.swift \
  Models/Highlight.swift \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/t22_runner"

"$TMP_DIR/t22_runner"
