#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/main.swift" <<'SWIFT'
import Foundation

testAppliesSameImageURLToAllScreens()
testNoScreensMakesNoCalls()
try testApplyWallpaperStopsOnError()
print("T23 verification passed")

private func testAppliesSameImageURLToAllScreens() {
    let imageURL = URL(fileURLWithPath: "/tmp/current_wallpaper.png")
    let screens = [101, 202, 303]
    var calls: [(URL, Int)] = []

    WallpaperSetter.applyWallpaper(imageURL: imageURL, screens: screens) { url, screen in
        calls.append((url, screen))
    }

    expect(calls.count == screens.count, "Expected one setDesktopImage call per screen")
    expect(calls.map(\.0) == Array(repeating: imageURL, count: screens.count), "Expected identical image URL for each call")
    expect(calls.map(\.1) == screens, "Expected screens to be visited in sequence")
}

private func testNoScreensMakesNoCalls() {
    let imageURL = URL(fileURLWithPath: "/tmp/current_wallpaper.png")
    var callCount = 0

    WallpaperSetter.applyWallpaper(imageURL: imageURL, screens: [Int]()) { _, _ in
        callCount += 1
    }

    expect(callCount == 0, "Expected no calls when there are no screens")
}

private func testApplyWallpaperStopsOnError() throws {
    enum SampleError: Error {
        case fail
    }

    let imageURL = URL(fileURLWithPath: "/tmp/current_wallpaper.png")
    let screens = [1, 2, 3]
    var processedScreens: [Int] = []

    do {
        try WallpaperSetter.applyWallpaper(imageURL: imageURL, screens: screens) { _, screen in
            processedScreens.append(screen)
            if screen == 2 {
                throw SampleError.fail
            }
        }
        fail("Expected error to be thrown from applyWallpaper")
    } catch SampleError.fail {
        // Expected path.
    } catch {
        fail("Expected SampleError.fail, got \(error)")
    }

    expect(processedScreens == [1, 2], "Expected iteration to stop at first thrown error")
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func fail(_ message: String) -> Never {
    fputs("Verification failure: \(message)\n", stderr)
    exit(1)
}
SWIFT

swiftc \
  -module-cache-path "$tmp_dir/module-cache" \
  App/WallpaperSetter.swift \
  "$tmp_dir/main.swift" \
  -o "$tmp_dir/verify_t23"

"$tmp_dir/verify_t23"
