import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t104_main failed: \(message)\n", stderr)
    exit(1)
}

private func assertEqual<T: Equatable>(_ lhs: T, _ rhs: T, _ message: String) {
    if lhs != rhs {
        fail("\(message). Expected \(rhs), got \(lhs)")
    }
}

private func makeFile(_ name: String) -> URL {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("kindlewall-t104-\(UUID().uuidString)-\(name)")
    try? "wallpaper".write(to: url, atomically: true, encoding: .utf8)
    return url
}

@main
enum VerifyT104 {
    static func main() {
        let persistedURL = makeFile("persisted.png")
        let liveURL = makeFile("live.png")
        let screens = [
            WallpaperSetter.ResolvedScreen(screen: "screen-a", identifier: "display-a", pixelWidth: 1, pixelHeight: 1),
            WallpaperSetter.ResolvedScreen(screen: "screen-b", identifier: "display-b", pixelWidth: 1, pixelHeight: 1)
        ]
        var appliedURLs: [URL] = []

        let outcome = WallpaperTopologyRestorer<String>.reapply(
            resolvedScreens: screens,
            storedWallpapers: [
                StoredGeneratedWallpaper(targetIdentifier: "display-a", fileURL: persistedURL)
            ],
            preferredSourceScreen: nil,
            sameScreen: { $0 == $1 },
            currentDesktopImageURL: { _ in liveURL },
            setDesktopImage: { url, _ in
                appliedURLs.append(url)
            }
        )

        assertEqual(outcome, WallpaperTopologyReapplyOutcome.reapplied, "Expected helper-compatible restorer to reapply from persisted shared assignment")
        assertEqual(appliedURLs, [persistedURL, persistedURL], "Expected persisted KindleWall wallpaper to win over live desktop state for every screen")

        print("verify_t104_main passed")
    }
}
