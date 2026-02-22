import AppKit
import Foundation

struct WallpaperGenerator {
    private let fileManager: FileManager
    private let appSupportDirectoryProvider: () -> URL
    private let mainScreenPixelSizeProvider: () -> CGSize?

    init(
        fileManager: FileManager = .default,
        appSupportDirectoryProvider: @escaping () -> URL = {
            AppSupportPaths.kindleWallDirectory(fileManager: .default)
        },
        mainScreenPixelSizeProvider: @escaping () -> CGSize? = {
            guard let screen = NSScreen.main else {
                return nil
            }

            let size = screen.frame.size
            let scale = screen.backingScaleFactor
            return CGSize(width: size.width * scale, height: size.height * scale)
        }
    ) {
        self.fileManager = fileManager
        self.appSupportDirectoryProvider = appSupportDirectoryProvider
        self.mainScreenPixelSizeProvider = mainScreenPixelSizeProvider
    }

    func generateWallpaper(highlight: Highlight, backgroundURL: URL?) -> URL {
        let outputSize = normalizedSize(mainScreenPixelSizeProvider() ?? CGSize(width: 1920, height: 1080))
        let backgroundImage = loadBackgroundImage(from: backgroundURL) ?? solidBlackImage(size: outputSize)

        let composedImage = composeImage(
            backgroundImage: backgroundImage,
            size: outputSize,
            highlight: highlight
        )

        let outputURL = appSupportDirectoryProvider().appendingPathComponent("current_wallpaper.png", isDirectory: false)
        writeImageAsPNG(composedImage, to: outputURL)
        return outputURL
    }

    private func loadBackgroundImage(from url: URL?) -> NSImage? {
        guard let url else {
            return nil
        }

        return NSImage(contentsOf: url)
    }

    private func solidBlackImage(size: CGSize) -> NSImage {
        renderImage(size: size) { rect in
            NSColor.black.setFill()
            rect.fill()
        }
    }

    private func composeImage(backgroundImage: NSImage, size: CGSize, highlight: Highlight) -> NSImage {
        renderImage(size: size) { rect in
            backgroundImage.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1.0)

            NSColor.black.withAlphaComponent(0.4).setFill()
            rect.fill(using: .sourceOver)

            drawTextOverlay(highlight: highlight, in: rect)
        }
    }

    private func drawTextOverlay(highlight: Highlight, in rect: NSRect) {
        let quoteText = highlight.quoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        let quote = quoteText.isEmpty ? " " : quoteText
        let attribution = "\(highlight.bookTitle) - \(highlight.author)".trimmingCharacters(in: .whitespacesAndNewlines)
        let maxTextWidth = rect.width * 0.7

        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .center
        paragraphStyle.lineBreakMode = .byWordWrapping

        let quoteAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 36, weight: .regular),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]
        let attributionAttributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 20, weight: .light),
            .foregroundColor: NSColor.white,
            .paragraphStyle: paragraphStyle
        ]

        let quoteBounds = (quote as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: quoteAttributes
        ).integral

        let attributionBounds = (attribution as NSString).boundingRect(
            with: CGSize(width: maxTextWidth, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributionAttributes
        ).integral

        let spacing: CGFloat = 24
        let totalHeight = quoteBounds.height + spacing + attributionBounds.height
        let baseY = (rect.height - totalHeight) / 2

        let attributionRect = NSRect(
            x: (rect.width - attributionBounds.width) / 2,
            y: baseY,
            width: attributionBounds.width,
            height: attributionBounds.height
        )

        let quoteRect = NSRect(
            x: (rect.width - quoteBounds.width) / 2,
            y: baseY + attributionBounds.height + spacing,
            width: quoteBounds.width,
            height: quoteBounds.height
        )

        (quote as NSString).draw(with: quoteRect, options: .usesLineFragmentOrigin, attributes: quoteAttributes)
        (attribution as NSString).draw(
            with: attributionRect,
            options: .usesLineFragmentOrigin,
            attributes: attributionAttributes
        )
    }

    private func renderImage(size: CGSize, draw: (NSRect) -> Void) -> NSImage {
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
            fatalError("Failed to allocate bitmap context for wallpaper rendering")
        }

        let rect = NSRect(origin: .zero, size: CGSize(width: CGFloat(width), height: CGFloat(height)))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        draw(rect)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rect.size)
        image.addRepresentation(bitmap)
        return image
    }

    private func writeImageAsPNG(_ image: NSImage, to url: URL) {
        guard
            let tiffData = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiffData),
            let pngData = bitmap.representation(using: .png, properties: [:])
        else {
            fatalError("Failed to encode wallpaper as PNG")
        }

        do {
            try fileManager.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try pngData.write(to: url, options: .atomic)
        } catch {
            fatalError("Failed to write wallpaper PNG to \(url.path): \(error)")
        }
    }

    private func normalizedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(size.width.rounded(.toNearestOrAwayFromZero), 1),
            height: max(size.height.rounded(.toNearestOrAwayFromZero), 1)
        )
    }
}
