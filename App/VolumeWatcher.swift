import Foundation

enum VolumeWatcher {
    private static let knownClippingsRelativePaths: [[String]] = [
        ["documents", "My Clippings.txt"],
        ["Documents", "My Clippings.txt"],
        ["My Clippings.txt"]
    ]

    static func findClippingsFile(on volume: URL, fileManager: FileManager = .default) -> URL? {
        for relativePathComponents in knownClippingsRelativePaths {
            let candidateURL = relativePathComponents.reduce(volume) { partialURL, component in
                partialURL.appendingPathComponent(component, isDirectory: false)
            }

            var isDirectory = ObjCBool(false)
            let exists = fileManager.fileExists(atPath: candidateURL.path, isDirectory: &isDirectory)
            if exists && !isDirectory.boolValue {
                return candidateURL
            }
        }

        return nil
    }
}
