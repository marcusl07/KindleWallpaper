import AppKit
import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t101_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertTrue(_ value: Bool, _ message: String) {
    if !value {
        fail(message)
    }
}

private func makeTemporaryDirectory() -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kindlewall-t101-\(UUID().uuidString)", isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    } catch {
        fail("Failed to create temp directory: \(error)")
    }
    return url
}

private func writePNG(at url: URL) {
    let image = NSImage(size: NSSize(width: 2, height: 2))
    image.lockFocus()
    NSColor.black.setFill()
    NSRect(x: 0, y: 0, width: 2, height: 2).fill()
    image.unlockFocus()

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let png = bitmap.representation(using: .png, properties: [:])
    else {
        fail("Failed to make PNG fixture")
    }

    do {
        try png.write(to: url)
    } catch {
        fail("Failed to write PNG fixture: \(error)")
    }
}

private func setModificationDate(_ date: Date, for url: URL) {
    do {
        try FileManager.default.setAttributes(
            [.modificationDate: date, .creationDate: date],
            ofItemAtPath: url.path
        )
    } catch {
        fail("Failed to set fixture dates: \(error)")
    }
}

@main
enum VerifyT101 {
    static func main() {
        let root = makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let generatedDirectory = root.appendingPathComponent("generated-wallpapers", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: generatedDirectory, withIntermediateDirectories: true)
        } catch {
            fail("Failed to create generated directory: \(error)")
        }

        let now = Date(timeIntervalSince1970: 2_000)
        let oldDate = now.addingTimeInterval(-3_600)
        let recentDate = now.addingTimeInterval(-120)

        let staleOld = generatedDirectory.appendingPathComponent("wallpaper_old_stale.png")
        let retainedOld = generatedDirectory.appendingPathComponent("wallpaper_old_retained.png")
        let recent = generatedDirectory.appendingPathComponent("wallpaper_recent_grace.png")
        let protected = generatedDirectory.appendingPathComponent("wallpaper_shared_assignment.png")

        for url in [staleOld, retainedOld, recent, protected] {
            writePNG(at: url)
        }
        setModificationDate(oldDate, for: staleOld)
        setModificationDate(oldDate, for: retainedOld)
        setModificationDate(recentDate, for: recent)
        setModificationDate(oldDate, for: protected)

        let generator = WallpaperGenerator(
            appSupportDirectoryProvider: { root },
            mainScreenPixelSizeProvider: { CGSize(width: 2, height: 2) },
            mainScreenScaleProvider: { 1 },
            retainedGeneratedFileCount: 1,
            protectedGeneratedWallpapersProvider: { [protected] },
            currentDateProvider: { now }
        )

        let highlight = Highlight(
            id: UUID(),
            bookId: nil,
            quoteText: "Quote",
            bookTitle: "Book",
            author: "Author",
            location: nil,
            dateAdded: nil,
            lastShownAt: nil,
            isEnabled: true
        )

        _ = generator.generateWallpapers(
            highlight: highlight,
            backgroundURL: nil,
            targets: [
                WallpaperGenerator.RenderTarget(identifier: "display-a", pixelWidth: 2, pixelHeight: 2)
            ],
            rotationID: "new"
        )

        assertTrue(FileManager.default.fileExists(atPath: recent.path), "Expected files newer than the cleanup grace interval to survive")
        assertTrue(FileManager.default.fileExists(atPath: protected.path), "Expected shared persisted assignment files to survive cleanup")
        assertTrue(FileManager.default.fileExists(atPath: retainedOld.path), "Expected retention count to keep the newest unprotected stale file after the generated file")
        assertTrue(!FileManager.default.fileExists(atPath: staleOld.path), "Expected old unprotected generated files beyond retention to be deleted")

        print("verify_t101_main passed")
    }
}
