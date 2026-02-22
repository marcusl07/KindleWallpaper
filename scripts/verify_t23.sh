#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cat > "$tmp_dir/main.swift" <<'SWIFT'
import Foundation

testApplyWallpapersUsesMatchingScreenIdentifiers()
testApplyWallpapersSkipsScreensWithoutAssignment()
try testApplyWallpapersStopsOnError()
print("T23 verification passed")

private func testApplyWallpapersUsesMatchingScreenIdentifiers() {
    let urlA = URL(fileURLWithPath: "/tmp/current_wallpaper_a.png")
    let urlB = URL(fileURLWithPath: "/tmp/current_wallpaper_b.png")
    let assignments = [
        WallpaperSetter.WallpaperAssignment(screenIdentifier: "display-101", imageURL: urlA),
        WallpaperSetter.WallpaperAssignment(screenIdentifier: "display-202", imageURL: urlB)
    ]
    let screens = [101, 202, 303]
    var calls: [(URL, Int)] = []

    WallpaperSetter.applyWallpapers(
        assignments: assignments,
        screens: screens,
        screenIdentifier: { screen, _ in "display-\(screen)" }
    ) { url, screen in
        calls.append((url, screen))
    }

    expect(calls.count == 2, "Expected one setDesktopImage call per matching screen")
    expect(calls[0].0 == urlA && calls[0].1 == 101, "Expected first matching screen to receive mapped URL")
    expect(calls[1].0 == urlB && calls[1].1 == 202, "Expected second matching screen to receive mapped URL")
}

private func testApplyWallpapersSkipsScreensWithoutAssignment() {
    let assignments = [
        WallpaperSetter.WallpaperAssignment(
            screenIdentifier: "display-404",
            imageURL: URL(fileURLWithPath: "/tmp/unused.png")
        )
    ]
    let screens = [1, 2, 3]
    var callCount = 0

    WallpaperSetter.applyWallpapers(
        assignments: assignments,
        screens: screens,
        screenIdentifier: { screen, _ in "display-\(screen)" }
    ) { _, _ in
        callCount += 1
    }

    expect(callCount == 0, "Expected no calls when no screen identifier matches an assignment")
}

private func testApplyWallpapersStopsOnError() throws {
    enum SampleError: Error {
        case fail
    }

    let urlA = URL(fileURLWithPath: "/tmp/current_wallpaper_a.png")
    let urlB = URL(fileURLWithPath: "/tmp/current_wallpaper_b.png")
    let assignments = [
        WallpaperSetter.WallpaperAssignment(screenIdentifier: "display-1", imageURL: urlA),
        WallpaperSetter.WallpaperAssignment(screenIdentifier: "display-2", imageURL: urlB)
    ]
    let screens = [1, 2, 3]
    var processedScreens: [Int] = []

    do {
        try WallpaperSetter.applyWallpapers(
            assignments: assignments,
            screens: screens,
            screenIdentifier: { screen, _ in "display-\(screen)" }
        ) { _, screen in
            processedScreens.append(screen)
            if screen == 2 {
                throw SampleError.fail
            }
        }
        fail("Expected error to be thrown from applyWallpapers")
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
