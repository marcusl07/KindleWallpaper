import Foundation
#if canImport(AppKit)
import AppKit
#endif

struct BackgroundImageStore {
    private enum Keys {
        static let backgroundImagePath = "backgroundImagePath"
    }

    private let fileManager: FileManager
    private let userDefaults: UserDefaults
    private let appSupportDirectoryURL: URL

    init(
        fileManager: FileManager = .default,
        userDefaults: UserDefaults = .standard,
        appSupportDirectoryURL: URL? = nil
    ) {
        self.fileManager = fileManager
        self.userDefaults = userDefaults

        if let appSupportDirectoryURL {
            self.appSupportDirectoryURL = appSupportDirectoryURL
        } else {
            self.appSupportDirectoryURL = AppSupportPaths.kindleWallDirectory(fileManager: fileManager)
        }
    }

    @discardableResult
    func saveBackgroundImage(from sourceURL: URL) throws -> URL {
        try ensureAppSupportDirectory()
        try removeExistingBackgroundFiles()

        let fileExtension = sourceURL.pathExtension
        let destinationName = fileExtension.isEmpty ? "background" : "background.\(fileExtension)"
        let destinationURL = appSupportDirectoryURL.appendingPathComponent(destinationName, isDirectory: false)

        try fileManager.copyItem(at: sourceURL, to: destinationURL)
        userDefaults.set(destinationURL.path, forKey: Keys.backgroundImagePath)

        return destinationURL
    }

    func loadBackgroundImageURL() -> URL? {
        guard let storedPath = userDefaults.string(forKey: Keys.backgroundImagePath),
              !storedPath.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: storedPath)
        guard fileManager.fileExists(atPath: url.path) else {
            userDefaults.removeObject(forKey: Keys.backgroundImagePath)
            return nil
        }

        return url
    }

    private func ensureAppSupportDirectory() throws {
        try fileManager.createDirectory(
            at: appSupportDirectoryURL,
            withIntermediateDirectories: true
        )
    }

    private func removeExistingBackgroundFiles() throws {
        guard fileManager.fileExists(atPath: appSupportDirectoryURL.path) else {
            return
        }

        let urls = try fileManager.contentsOfDirectory(
            at: appSupportDirectoryURL,
            includingPropertiesForKeys: nil
        )

        for url in urls {
            let name = url.lastPathComponent
            if name == "background" || name.hasPrefix("background.") {
                try fileManager.removeItem(at: url)
            }
        }
    }
}

#if canImport(AppKit)
final class BackgroundImageLoader {
    enum Outcome: Equatable {
        case noImageConfigured
        case success
        case missingFile(path: String)
        case unreadableFile(path: String)
        case decodeFailed(path: String)
    }

    struct LoadResult {
        let image: NSImage?
        let outcome: Outcome
    }

    static let shared = BackgroundImageLoader()

    private struct FileIdentity: Equatable {
        let modificationDate: Date
        let fileSize: Int
    }

    private struct CachedImage {
        let identity: FileIdentity
        let image: NSImage
    }

    private enum WarningKind: String {
        case missingFile
        case unreadableFile
        case decodeFailed
    }

    private struct WarningKey: Hashable {
        let kind: WarningKind
        let path: String
    }

    private let fileManager: FileManager
    private let loadImage: (URL) -> NSImage?
    private let logger: (String) -> Void
    private let lock = NSLock()

    private var cachedImagesByPath: [String: CachedImage] = [:]
    private var emittedWarningKeys: Set<WarningKey> = []

    init(
        fileManager: FileManager = .default,
        loadImage: @escaping (URL) -> NSImage? = { NSImage(contentsOf: $0) },
        logger: @escaping (String) -> Void = { message in
            fputs("[KindleWall] \(message)\n", stderr)
        }
    ) {
        self.fileManager = fileManager
        self.loadImage = loadImage
        self.logger = logger
    }

    func load(from url: URL?) -> LoadResult {
        guard let url else {
            return LoadResult(image: nil, outcome: .noImageConfigured)
        }

        let path = url.path
        guard fileManager.fileExists(atPath: path) else {
            invalidateCache(forPath: path)
            emitWarningOnce(kind: .missingFile, path: path, message: "Background image missing at path: \(path)")
            return LoadResult(image: nil, outcome: .missingFile(path: path))
        }

        guard fileManager.isReadableFile(atPath: path) else {
            invalidateCache(forPath: path)
            emitWarningOnce(kind: .unreadableFile, path: path, message: "Background image is not readable at path: \(path)")
            return LoadResult(image: nil, outcome: .unreadableFile(path: path))
        }

        let identity = fileIdentity(for: url)
        if let identity, let cachedImage = cachedImage(forPath: path, identity: identity) {
            return LoadResult(image: cachedImage, outcome: .success)
        }

        guard let image = loadImage(url) else {
            invalidateCache(forPath: path)
            emitWarningOnce(
                kind: .decodeFailed,
                path: path,
                message: "Background image failed to decode at path: \(path). Falling back to solid black."
            )
            return LoadResult(image: nil, outcome: .decodeFailed(path: path))
        }

        if let identity {
            cache(image: image, forPath: path, identity: identity)
        } else {
            invalidateCache(forPath: path)
        }

        return LoadResult(image: image, outcome: .success)
    }

    private func fileIdentity(for url: URL) -> FileIdentity? {
        var uncachedURL = url
        uncachedURL.removeAllCachedResourceValues()
        let values = try? uncachedURL.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        guard
            let modificationDate = values?.contentModificationDate,
            let fileSize = values?.fileSize
        else {
            return nil
        }
        return FileIdentity(modificationDate: modificationDate, fileSize: fileSize)
    }

    private func cachedImage(forPath path: String, identity: FileIdentity) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }

        guard let cached = cachedImagesByPath[path] else {
            return nil
        }
        guard cached.identity == identity else {
            return nil
        }
        return cached.image
    }

    private func cache(image: NSImage, forPath path: String, identity: FileIdentity) {
        lock.lock()
        cachedImagesByPath[path] = CachedImage(identity: identity, image: image)
        lock.unlock()
    }

    private func invalidateCache(forPath path: String) {
        lock.lock()
        cachedImagesByPath.removeValue(forKey: path)
        lock.unlock()
    }

    private func emitWarningOnce(kind: WarningKind, path: String, message: String) {
        let warningKey = WarningKey(kind: kind, path: path)

        lock.lock()
        let inserted = emittedWarningKeys.insert(warningKey).inserted
        lock.unlock()

        guard inserted else {
            return
        }
        logger(message)
    }
}
#endif
