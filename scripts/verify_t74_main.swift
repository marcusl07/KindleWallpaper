import AppKit
import Foundation

func testFormattedAttributionOmitsBlankMetadata() {
    expect(
        WallpaperGenerator.formattedAttribution(bookTitle: nil, author: nil) == nil,
        "Expected nil attribution when both title and author are nil"
    )
    expect(
        WallpaperGenerator.formattedAttribution(bookTitle: " \n ", author: "\t") == nil,
        "Expected nil attribution when title and author are whitespace-only"
    )
    expect(
        WallpaperGenerator.formattedAttribution(bookTitle: "Title Only", author: "") == "Title Only",
        "Expected title-only attribution when author is blank"
    )
    expect(
        WallpaperGenerator.formattedAttribution(bookTitle: "", author: "Author Only") == "Author Only",
        "Expected author-only attribution when title is blank"
    )
    expect(
        WallpaperGenerator.formattedAttribution(bookTitle: "Book", author: "Author") == "Book - Author",
        "Expected full attribution when both title and author are present"
    )
}

func testGenerateWallpapersOmitsAttributionLineWhenMetadataBlank() throws {
    let fixture = try TestFixture.make()
    defer { fixture.cleanup() }

    let target = WallpaperGenerator.RenderTarget(
        identifier: "display-1",
        pixelWidth: 1200,
        pixelHeight: 800
    )

    let blankMetadataOutput = fixture.generator.generateWallpapers(
        highlight: sampleHighlight(bookTitle: " \n ", author: "\t"),
        backgroundURL: nil,
        targets: [target],
        rotationID: "t74-blank"
    )

    let populatedMetadataOutput = fixture.generator.generateWallpapers(
        highlight: sampleHighlight(bookTitle: "Book", author: "Author"),
        backgroundURL: nil,
        targets: [target],
        rotationID: "t74-full"
    )

    guard
        let blankURL = blankMetadataOutput.first?.fileURL,
        let fullURL = populatedMetadataOutput.first?.fileURL
    else {
        fail("Expected generated wallpaper outputs for T74 verification")
        return
    }

    let blankClusters = try brightRowClusterCount(at: blankURL)
    let fullClusters = try brightRowClusterCount(at: fullURL)

    expect(
        blankClusters == 1,
        "Expected only one text row cluster when attribution metadata is blank, got \(blankClusters)"
    )
    expect(
        fullClusters >= 2,
        "Expected separate quote and attribution clusters when attribution metadata exists, got \(fullClusters)"
    )
}

func sampleHighlight(bookTitle: String, author: String) -> Highlight {
    Highlight(
        id: UUID(),
        bookId: UUID(),
        quoteText: "Centered quote for attribution rendering verification.",
        bookTitle: bookTitle,
        author: author,
        location: "100-101",
        dateAdded: nil,
        lastShownAt: nil
    )
}

func brightRowClusterCount(at url: URL) throws -> Int {
    let data = try Data(contentsOf: url)
    guard
        let bitmap = NSBitmapImageRep(data: data),
        let rawPixels = bitmap.bitmapData
    else {
        throw NSError(
            domain: "VerifyT74",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Failed to decode generated PNG"]
        )
    }

    let bytesPerPixel = max(bitmap.bitsPerPixel / 8, 4)
    var activeRows: [Bool] = []
    activeRows.reserveCapacity(bitmap.pixelsHigh)

    for y in 0..<bitmap.pixelsHigh {
        var brightPixelCount = 0
        for x in 0..<bitmap.pixelsWide {
            let offset = (y * bitmap.bytesPerRow) + (x * bytesPerPixel)
            let red = rawPixels[offset]
            let green = rawPixels[offset + 1]
            let blue = rawPixels[offset + 2]

            if red >= 220 && green >= 220 && blue >= 220 {
                brightPixelCount += 1
            }
        }

        activeRows.append(brightPixelCount >= 3)
    }

    var clusterCount = 0
    var isInsideCluster = false
    for isActive in activeRows {
        if isActive && !isInsideCluster {
            clusterCount += 1
            isInsideCluster = true
        } else if !isActive {
            isInsideCluster = false
        }
    }

    return clusterCount
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fputs("Verification failure: \(message)\n", stderr)
        exit(1)
    }
}

func fail(_ message: String) {
    fputs("Verification failure: \(message)\n", stderr)
    exit(1)
}

struct TestFixture {
    let rootURL: URL
    let appSupportURL: URL
    let generator: WallpaperGenerator

    static func make() throws -> TestFixture {
        let fileManager = FileManager.default
        let rootURL = fileManager.temporaryDirectory.appendingPathComponent(
            "kindlewall-t74-\(UUID().uuidString)",
            isDirectory: true
        )
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let appSupportURL = rootURL.appendingPathComponent("ApplicationSupport/KindleWall", isDirectory: true)
        let generator = WallpaperGenerator(
            fileManager: fileManager,
            appSupportDirectoryProvider: { appSupportURL },
            mainScreenPixelSizeProvider: { CGSize(width: 1920, height: 1080) }
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
    testFormattedAttributionOmitsBlankMetadata()
    try testGenerateWallpapersOmitsAttributionLineWhenMetadataBlank()
    print("T74 verification passed")
} catch {
    fputs("Verification failure: \(error)\n", stderr)
    exit(1)
}
