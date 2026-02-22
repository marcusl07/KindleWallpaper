import Foundation

enum AppSupportPaths {
    static func kindleWallDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("KindleWall", isDirectory: true)
    }
}
