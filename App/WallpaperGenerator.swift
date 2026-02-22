import AppKit
import Foundation

struct WallpaperGenerator {
    struct RenderTarget: Equatable {
        let identifier: String
        let pixelWidth: Int
        let pixelHeight: Int
    }

    struct GeneratedWallpaper: Equatable {
        let targetIdentifier: String
        let fileURL: URL
    }

    private enum Constants {
        static let generatedWallpapersDirectoryName = "generated-wallpapers"
        static let generatedWallpaperPrefix = "wallpaper_"
        static let defaultRetainedGeneratedFiles = 5
    }

    private let fileManager: FileManager
    private let appSupportDirectoryProvider: () -> URL
    private let mainScreenPixelSizeProvider: () -> CGSize?
    private let retainedGeneratedFileCount: Int

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
        },
        retainedGeneratedFileCount: Int = Constants.defaultRetainedGeneratedFiles
    ) {
        self.fileManager = fileManager
        self.appSupportDirectoryProvider = appSupportDirectoryProvider
        self.mainScreenPixelSizeProvider = mainScreenPixelSizeProvider
        self.retainedGeneratedFileCount = max(retainedGeneratedFileCount, 1)
    }

    func generateWallpaper(highlight: Highlight, backgroundURL: URL?) -> URL {
        let fallbackSize = normalizedSize(mainScreenPixelSizeProvider() ?? CGSize(width: 1920, height: 1080))
        let fallbackTarget = RenderTarget(
            identifier: "main",
            pixelWidth: Int(fallbackSize.width),
            pixelHeight: Int(fallbackSize.height)
        )
        let generatedWallpapers = generateWallpapers(
            highlight: highlight,
            backgroundURL: backgroundURL,
            targets: [fallbackTarget]
        )

        guard let outputURL = generatedWallpapers.first?.fileURL else {
            fatalError("Failed to generate fallback wallpaper")
        }

        return outputURL
    }

    func generateWallpapers(
        highlight: Highlight,
        backgroundURL: URL?,
        targets: [RenderTarget],
        rotationID: String = UUID().uuidString
    ) -> [GeneratedWallpaper] {
        guard !targets.isEmpty else {
            return []
        }

        let outputDirectory = generatedWallpapersDirectoryURL()
        do {
            try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        } catch {
            fatalError("Failed to create generated wallpapers directory at \(outputDirectory.path): \(error)")
        }

        let loadedBackgroundImage = loadBackgroundImage(from: backgroundURL)
        var generatedWallpapers: [GeneratedWallpaper] = []
        generatedWallpapers.reserveCapacity(targets.count)

        for target in targets {
            let outputSize = normalizedSize(
                CGSize(width: CGFloat(max(target.pixelWidth, 1)), height: CGFloat(max(target.pixelHeight, 1)))
            )
            let backgroundImage = loadedBackgroundImage ?? solidBlackImage(size: outputSize)
            let composedImage = composeImage(
                backgroundImage: backgroundImage,
                size: outputSize,
                highlight: highlight
            )
            let outputFilename = outputFilename(
                rotationID: rotationID,
                targetIdentifier: target.identifier
            )
            let outputURL = outputDirectory.appendingPathComponent(outputFilename, isDirectory: false)
            writeImageAsPNG(composedImage, to: outputURL)
            generatedWallpapers.append(
                GeneratedWallpaper(
                    targetIdentifier: target.identifier,
                    fileURL: outputURL
                )
            )
        }

        cleanupGeneratedWallpapers(in: outputDirectory)
        return generatedWallpapers
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

    private func generatedWallpapersDirectoryURL() -> URL {
        appSupportDirectoryProvider()
            .appendingPathComponent(Constants.generatedWallpapersDirectoryName, isDirectory: true)
    }

    private func outputFilename(rotationID: String, targetIdentifier: String) -> String {
        let sanitizedTargetIdentifier = sanitizeIdentifier(targetIdentifier)
        let sanitizedRotationID = sanitizeIdentifier(rotationID)
        return "\(Constants.generatedWallpaperPrefix)\(sanitizedRotationID)_\(sanitizedTargetIdentifier).png"
    }

    private func sanitizeIdentifier(_ value: String) -> String {
        let collapsed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let result = collapsed.replacingOccurrences(
            of: "[^A-Za-z0-9_-]",
            with: "_",
            options: .regularExpression
        )
        return result.isEmpty ? "unknown" : result
    }

    private func cleanupGeneratedWallpapers(in directoryURL: URL) {
        do {
            let fileURLs = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .contentModificationDateKey,
                    .creationDateKey
                ],
                options: [.skipsHiddenFiles]
            )

            let generatedFiles = fileURLs.filter { url in
                let filename = url.lastPathComponent
                guard filename.hasPrefix(Constants.generatedWallpaperPrefix) else {
                    return false
                }
                guard url.pathExtension.lowercased() == "png" else {
                    return false
                }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return values?.isRegularFile ?? false
            }

            guard generatedFiles.count > retainedGeneratedFileCount else {
                return
            }

            let sortedFiles = generatedFiles.sorted { lhs, rhs in
                resourceTimestamp(for: lhs) > resourceTimestamp(for: rhs)
            }

            let staleFiles = sortedFiles.dropFirst(retainedGeneratedFileCount)
            for staleFile in staleFiles {
                try? fileManager.removeItem(at: staleFile)
            }
        } catch {
            // Retention cleanup is best-effort and should not block wallpaper updates.
        }
    }

    private func resourceTimestamp(for url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey])
        return values?.contentModificationDate
            ?? values?.creationDate
            ?? .distantPast
    }

    private func normalizedSize(_ size: CGSize) -> CGSize {
        CGSize(
            width: max(size.width.rounded(.toNearestOrAwayFromZero), 1),
            height: max(size.height.rounded(.toNearestOrAwayFromZero), 1)
        )
    }
}
