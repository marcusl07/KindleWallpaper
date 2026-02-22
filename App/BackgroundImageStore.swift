import Foundation

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
            let rootURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.appSupportDirectoryURL = rootURL.appendingPathComponent("KindleWall", isDirectory: true)
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
