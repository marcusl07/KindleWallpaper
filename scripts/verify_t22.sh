#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

TMP_DIR="$(mktemp -d /tmp/kindlewall_t22.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import AppKit
import Foundation

func testGenerateWallpapersCreatesPerTargetFilesAndSizes() throws {
    let fixture = try TestFixture.make()
    defer { fixture.cleanup() }

    let targets = [
        WallpaperGenerator.RenderTarget(identifier: "display-111", pixelWidth: 1200, pixelHeight: 800),
        WallpaperGenerator.RenderTarget(identifier: "display-222", pixelWidth: 2000, pixelHeight: 1100)
    ]

    let outputs = fixture.generator.generateWallpapers(
        highlight: sampleHighlight(quote: "A short quote for per-screen coverage."),
        backgroundURL: nil,
        targets: targets,
        rotationID: "rotation-a"
    )

    expect(outputs.count == 2, "Expected one generated wallpaper per target screen")
    expect(Set(outputs.map { $0.targetIdentifier }) == Set(targets.map { $0.identifier }), "Expected target identifiers to round-trip")
    expect(Set(outputs.map { $0.fileURL.path }).count == 2, "Expected generated file URLs to be unique per target")

    for output in outputs {
        expect(FileManager.default.fileExists(atPath: output.fileURL.path), "Expected generated file to exist for \(output.targetIdentifier)")
        expect(output.fileURL.lastPathComponent.hasPrefix("wallpaper_rotation-a_"), "Expected prefixed filename format for generated wallpaper")

        let dimensions = try imageDimensions(at: output.fileURL)
        if output.targetIdentifier == "display-111" {
            expect(dimensions.width == 1200 && dimensions.height == 800, "Expected display-111 output dimensions to match target")
        }
        if output.targetIdentifier == "display-222" {
            expect(dimensions.width == 2000 && dimensions.height == 1100, "Expected display-222 output dimensions to match target")
        }
    }
}

func testGenerateWallpapersScalesTextByBackingScaleFactor() throws {
    let fixture = try TestFixture.make()
    defer { fixture.cleanup() }

    let outputs = fixture.generator.generateWallpapers(
        highlight: sampleHighlight(quote: "Scale-sensitive text"),
        backgroundURL: nil,
        targets: [
            WallpaperGenerator.RenderTarget(
                identifier: "scale-1x",
                pixelWidth: 1200,
                pixelHeight: 800,
                backingScaleFactor: 1.0
            ),
            WallpaperGenerator.RenderTarget(
                identifier: "scale-2x",
                pixelWidth: 2400,
                pixelHeight: 1600,
                backingScaleFactor: 2.0
            )
        ],
        rotationID: "rotation-scale"
    )

    let outputsByIdentifier = Dictionary(uniqueKeysWithValues: outputs.map { ($0.targetIdentifier, $0) })
    guard
        let oneX = outputsByIdentifier["scale-1x"],
        let twoX = outputsByIdentifier["scale-2x"]
    else {
        throw NSError(
            domain: "VerifyT22",
            code: 4,
            userInfo: [NSLocalizedDescriptionKey: "Missing generated wallpapers for scale verification"]
        )
    }

    let oneXBrightPixels = try brightPixelCount(at: oneX.fileURL)
    let twoXBrightPixels = try brightPixelCount(at: twoX.fileURL)
    expect(oneXBrightPixels > 0, "Expected 1x output to contain bright text pixels")

    let ratio = Double(twoXBrightPixels) / Double(oneXBrightPixels)
    expect(
        ratio > 2.5,
        "Expected 2x target to render a larger text footprint, bright-pixel ratio was \(ratio)"
    )
}

func testGenerateWallpapersUsesUniqueFilenameAcrossRotations() throws {
    let fixture = try TestFixture.make()
    defer { fixture.cleanup() }

    let target = WallpaperGenerator.RenderTarget(identifier: "display-1", pixelWidth: 1440, pixelHeight: 900)

    let first = fixture.generator.generateWallpapers(
        highlight: sampleHighlight(quote: "First run"),
        backgroundURL: nil,
        targets: [target]
    )
    let second = fixture.generator.generateWallpapers(
        highlight: sampleHighlight(quote: "Second run"),
        backgroundURL: nil,
        targets: [target]
    )

    expect(first.count == 1 && second.count == 1, "Expected one output for each single-target rotation")
    expect(first[0].fileURL != second[0].fileURL, "Expected unique wallpaper filename per rotation")
}

func testCleanupRetainsLastFiveGeneratedFiles() throws {
    let fixture = try TestFixture.make(retainedGeneratedFileCount: 5)
    defer { fixture.cleanup() }

    let target = WallpaperGenerator.RenderTarget(identifier: "display-1", pixelWidth: 1000, pixelHeight: 600)

    for index in 1...7 {
        _ = fixture.generator.generateWallpapers(
            highlight: sampleHighlight(quote: "Rotation \(index)"),
            backgroundURL: nil,
            targets: [target],
            rotationID: "rot-\(index)"
        )
        Thread.sleep(forTimeInterval: 0.05)
    }

    let generatedDirectory = fixture.appSupportURL.appendingPathComponent("generated-wallpapers", isDirectory: true)
    let remaining = try FileManager.default.contentsOfDirectory(
        at: generatedDirectory,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles]
    )
    .map(\.lastPathComponent)
    .filter { $0.hasPrefix("wallpaper_") && $0.hasSuffix(".png") }

    expect(remaining.count == 5, "Expected retention cleanup to keep only five generated wallpapers")
    expect(remaining.allSatisfy { !$0.contains("rot-1") && !$0.contains("rot-2") }, "Expected oldest generated files to be cleaned up")
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

func imageDimensions(at url: URL) throws -> (width: Int, height: Int) {
    guard
        let data = try? Data(contentsOf: url),
        let bitmap = NSBitmapImageRep(data: data)
    else {
        throw NSError(domain: "VerifyT22", code: 3, userInfo: [NSLocalizedDescriptionKey: "Failed to decode generated PNG"])
    }

    return (bitmap.pixelsWide, bitmap.pixelsHigh)
}

func brightPixelCount(at url: URL) throws -> Int {
    let data = try Data(contentsOf: url)
    guard
        let bitmap = NSBitmapImageRep(data: data),
        let rawPixels = bitmap.bitmapData
    else {
        throw NSError(domain: "VerifyT22", code: 5, userInfo: [NSLocalizedDescriptionKey: "Failed to decode bitmap"])
    }

    let bytesPerPixel = max(bitmap.bitsPerPixel / 8, 4)
    var brightCount = 0
    for y in 0..<bitmap.pixelsHigh {
        for x in 0..<bitmap.pixelsWide {
            let offset = (y * bitmap.bytesPerRow) + (x * bytesPerPixel)
            let red = rawPixels[offset]
            let green = rawPixels[offset + 1]
            let blue = rawPixels[offset + 2]

            if red >= 220 && green >= 220 && blue >= 220 {
                brightCount += 1
            }
        }
    }

    return brightCount
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

    static func make(retainedGeneratedFileCount: Int = 5) throws -> TestFixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent("kindlewall-t22-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let appSupportURL = rootURL.appendingPathComponent("ApplicationSupport/KindleWall", isDirectory: true)
        let generator = WallpaperGenerator(
            fileManager: fileManager,
            appSupportDirectoryProvider: { appSupportURL },
            mainScreenPixelSizeProvider: { CGSize(width: 1920, height: 1080) },
            retainedGeneratedFileCount: retainedGeneratedFileCount
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
    try testGenerateWallpapersCreatesPerTargetFilesAndSizes()
    try testGenerateWallpapersScalesTextByBackingScaleFactor()
    try testGenerateWallpapersUsesUniqueFilenameAcrossRotations()
    try testCleanupRetainsLastFiveGeneratedFiles()
    print("T22 verification passed")
} catch {
    fputs("Verification failure: \(error)\n", stderr)
    exit(1)
}
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  App/AppSupportPaths.swift \
  App/BackgroundImageStore.swift \
  App/BackgroundImageLoader.swift \
  App/WallpaperGenerator.swift \
  Models/Highlight.swift \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/t22_runner"

"$TMP_DIR/t22_runner"
