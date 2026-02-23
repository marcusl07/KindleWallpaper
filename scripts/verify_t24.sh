#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t24.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

func testLastChangedAtUserDefaultsHelperRoundTripsAndClears() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    assertEqual(fixture.defaults.lastChangedAt, nil, "Expected missing lastChangedAt to default to nil")

    let timestamp = Date(timeIntervalSince1970: 1_735_704_000.125)
    fixture.defaults.lastChangedAt = timestamp
    assertDateEqual(fixture.defaults.lastChangedAt, timestamp, "Expected lastChangedAt to round trip through UserDefaults helper")

    fixture.defaults.lastChangedAt = nil
    assertEqual(fixture.defaults.lastChangedAt, nil, "Expected setting lastChangedAt to nil to remove the value")
}

func testLastChangedAtUserDefaultsHelperParsesLegacyFormats() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    fixture.defaults.set(1_735_704_000.25, forKey: "lastChangedAt")
    assertDateEqual(
        fixture.defaults.lastChangedAt,
        Date(timeIntervalSince1970: 1_735_704_000.25),
        "Expected helper to parse numeric timestamp values"
    )

    fixture.defaults.set("1735704000.5", forKey: "lastChangedAt")
    assertDateEqual(
        fixture.defaults.lastChangedAt,
        Date(timeIntervalSince1970: 1_735_704_000.5),
        "Expected helper to parse numeric string timestamp values"
    )

    fixture.defaults.set("2025-01-01T12:00:00Z", forKey: "lastChangedAt")
    assertDateEqual(
        fixture.defaults.lastChangedAt,
        Date(timeIntervalSince1970: 1_735_732_800),
        "Expected helper to parse ISO8601 string values"
    )
}

func testAppStateInitLoadsPersistedLastChangedAt() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let persisted = Date(timeIntervalSince1970: 1_735_800_123)
    fixture.defaults.lastChangedAt = persisted

    let appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        now: { Date(timeIntervalSince1970: 0) }
    )

    assertDateEqual(appState.lastChangedAt, persisted, "Expected AppState to load lastChangedAt from UserDefaults on init")
}

func testRotateWallpaperHappyPathCallsInOrderAndUpdatesState() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let highlight = sampleHighlight(
        id: UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE")!,
        quoteText: "Stay hungry. Stay foolish."
    )
    let backgroundURL = URL(fileURLWithPath: "/tmp/background.jpg")
    let generatedURL = URL(fileURLWithPath: "/tmp/current_wallpaper.png")
    let nowValue = Date(timeIntervalSince1970: 1_735_900_100)
    var calls: [String] = []
    var generatedArguments: (Highlight, URL?)?
    var setWallpaperArgument: URL?
    var markedID: UUID?

    let appState = AppState(
        userDefaults: fixture.defaults,
        currentQuotePreview: "old preview",
        pickNextHighlight: {
            calls.append("pick")
            return highlight
        },
        loadBackgroundImageURL: {
            calls.append("loadBackground")
            return backgroundURL
        },
        generateWallpaper: { incomingHighlight, incomingBackgroundURL in
            calls.append("generate")
            generatedArguments = (incomingHighlight, incomingBackgroundURL)
            return generatedURL
        },
        setWallpaper: { url in
            calls.append("set")
            setWallpaperArgument = url
        },
        markHighlightShown: { id in
            calls.append("mark")
            markedID = id
        },
        now: {
            calls.append("now")
            return nowValue
        }
    )

    let didRotate = appState.rotateWallpaper()
    assertEqual(didRotate, true, "Expected rotateWallpaper to report success when a highlight is selected")

    assertEqual(
        calls,
        ["pick", "loadBackground", "generate", "set", "mark", "now"],
        "Expected rotateWallpaper to orchestrate dependencies in T24 order"
    )
    assertEqual(generatedArguments?.0.id, highlight.id, "Expected generateWallpaper to receive picked highlight")
    assertEqual(generatedArguments?.1, backgroundURL, "Expected generateWallpaper to receive loaded background URL")
    assertEqual(setWallpaperArgument, generatedURL, "Expected setWallpaper to receive generated wallpaper URL")
    assertEqual(markedID, highlight.id, "Expected markHighlightShown to be called with picked highlight id")
    assertEqual(appState.currentQuotePreview, highlight.quoteText, "Expected current quote preview to update after rotation")
    assertDateEqual(appState.lastChangedAt, nowValue, "Expected AppState.lastChangedAt to update after rotation")
    assertDateEqual(fixture.defaults.lastChangedAt, nowValue, "Expected UserDefaults.lastChangedAt to update after rotation")
}

func testRotateWallpaperSkipsWorkWhenNoHighlightIsAvailable() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    var loadBackgroundCallCount = 0
    var generateCallCount = 0
    var setWallpaperCallCount = 0
    var markCallCount = 0
    var nowCallCount = 0

    let appState = AppState(
        userDefaults: fixture.defaults,
        currentQuotePreview: "existing preview",
        pickNextHighlight: { nil },
        loadBackgroundImageURL: {
            loadBackgroundCallCount += 1
            return nil
        },
        generateWallpaper: { _, _ in
            generateCallCount += 1
            return URL(fileURLWithPath: "/tmp/unused.png")
        },
        setWallpaper: { _ in
            setWallpaperCallCount += 1
        },
        markHighlightShown: { _ in
            markCallCount += 1
        },
        now: {
            nowCallCount += 1
            return Date(timeIntervalSince1970: 0)
        }
    )

    let didRotate = appState.rotateWallpaper()
    assertEqual(didRotate, false, "Expected rotateWallpaper to report failure when no highlight is available")

    assertEqual(loadBackgroundCallCount, 0, "Expected no background load when no highlight is available")
    assertEqual(generateCallCount, 0, "Expected no wallpaper generation when no highlight is available")
    assertEqual(setWallpaperCallCount, 0, "Expected no wallpaper set when no highlight is available")
    assertEqual(markCallCount, 0, "Expected no markHighlightShown call when no highlight is available")
    assertEqual(nowCallCount, 0, "Expected no clock read when no highlight is available")
    assertEqual(appState.currentQuotePreview, "existing preview", "Expected current quote preview to remain unchanged")
    assertEqual(appState.lastChangedAt, nil, "Expected AppState.lastChangedAt to remain unchanged")
    assertEqual(fixture.defaults.lastChangedAt, nil, "Expected UserDefaults.lastChangedAt to remain unchanged")
}

func testRotateWallpaperPassesNilBackgroundToGenerator() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let highlight = sampleHighlight(quoteText: "Quote")
    var passedBackgroundURL: URL??

    let appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: { highlight },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, backgroundURL in
            passedBackgroundURL = backgroundURL
            return URL(fileURLWithPath: "/tmp/generated.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        now: { Date(timeIntervalSince1970: 1_735_910_000) }
    )

    let didRotate = appState.rotateWallpaper()
    assertEqual(didRotate, true, "Expected rotateWallpaper to report success when generation runs")
    assertEqual(passedBackgroundURL != nil, true, "Expected generateWallpaper to be called")
    assertEqual(passedBackgroundURL!, nil, "Expected nil background URL to flow into generator")
}

func testRotateWallpaperReentrancyGuardPreventsNestedWork() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let highlight = sampleHighlight(quoteText: "First quote")
    var appState: AppState!
    var pickCallCount = 0
    var generateCallCount = 0
    var setCallCount = 0
    var markCallCount = 0
    var nowCallCount = 0

    appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: {
            pickCallCount += 1
            return highlight
        },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in
            generateCallCount += 1
            return URL(fileURLWithPath: "/tmp/generated.png")
        },
        setWallpaper: { _ in
            setCallCount += 1
            appState.rotateWallpaper()
        },
        markHighlightShown: { _ in
            markCallCount += 1
        },
        now: {
            nowCallCount += 1
            return Date(timeIntervalSince1970: 1_735_920_000)
        }
    )

    let didRotate = appState.rotateWallpaper()
    assertEqual(didRotate, true, "Expected outer rotateWallpaper call to report success")

    assertEqual(pickCallCount, 1, "Expected nested rotateWallpaper call to be ignored while rotation is in progress")
    assertEqual(generateCallCount, 1, "Expected nested rotateWallpaper call to skip generation")
    assertEqual(setCallCount, 1, "Expected nested rotateWallpaper call to skip wallpaper application")
    assertEqual(markCallCount, 1, "Expected nested rotateWallpaper call to skip markHighlightShown")
    assertEqual(nowCallCount, 1, "Expected nested rotateWallpaper call to skip timestamp update")
}

func testRotateWallpaperUsesPerScreenPipelineWhenConfigured() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let highlight = sampleHighlight(quoteText: "Per-screen quote")
    let backgroundURL = URL(fileURLWithPath: "/tmp/background.jpg")
    let targets: [AppState.WallpaperTarget] = [
        (identifier: "display-101", pixelWidth: 1400, pixelHeight: 900, backingScaleFactor: 1.0),
        (identifier: "display-202", pixelWidth: 2400, pixelHeight: 1350, backingScaleFactor: 2.0)
    ]

    var calls: [String] = []
    var legacyGenerateCallCount = 0
    var legacySetCallCount = 0
    var appliedWallpapers: [AppState.GeneratedWallpaper] = []
    var markedID: UUID?

    let appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: {
            calls.append("pick")
            return highlight
        },
        loadBackgroundImageURL: {
            calls.append("loadBackground")
            return backgroundURL
        },
        generateWallpaper: { _, _ in
            legacyGenerateCallCount += 1
            return URL(fileURLWithPath: "/tmp/legacy.png")
        },
        setWallpaper: { _ in
            legacySetCallCount += 1
        },
        fetchWallpaperTargets: {
            calls.append("targets")
            return targets
        },
        generateWallpapers: { incomingHighlight, incomingBackgroundURL, incomingTargets in
            calls.append("generateMany")
            assertEqual(incomingHighlight.id, highlight.id, "Expected multi-screen generation to use picked highlight")
            assertEqual(incomingBackgroundURL, backgroundURL, "Expected multi-screen generation to use loaded background")
            assertEqual(incomingTargets.count, targets.count, "Expected generation to receive all fetched targets")
            return incomingTargets.map { target in
                (
                    targetIdentifier: target.identifier,
                    fileURL: URL(fileURLWithPath: "/tmp/\(target.identifier).png")
                )
            }
        },
        setWallpapers: { generated in
            calls.append("setMany")
            appliedWallpapers = generated
        },
        markHighlightShown: { id in
            calls.append("mark")
            markedID = id
        },
        now: {
            calls.append("now")
            return Date(timeIntervalSince1970: 1_735_930_000)
        }
    )

    let didRotate = appState.rotateWallpaper()
    assertEqual(didRotate, true, "Expected rotateWallpaper to succeed when per-screen pipeline is configured")
    assertEqual(legacyGenerateCallCount, 0, "Expected legacy single-wallpaper generation to be skipped")
    assertEqual(legacySetCallCount, 0, "Expected legacy single-wallpaper apply to be skipped")
    assertEqual(appliedWallpapers.count, 2, "Expected one generated wallpaper per target")
    assertEqual(Set(appliedWallpapers.map { $0.targetIdentifier }), Set(targets.map { $0.identifier }), "Expected generated wallpapers to cover all targets")
    assertEqual(markedID, highlight.id, "Expected highlight to be marked as shown after per-screen update")
    assertEqual(calls, ["pick", "loadBackground", "targets", "generateMany", "setMany", "mark", "now"], "Expected per-screen pipeline orchestration order")
}

func testRotateWallpaperPerScreenPipelineRejectsIdentifierMismatch() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let highlight = sampleHighlight(quoteText: "Mismatch quote")
    var setWallpapersCallCount = 0
    var markCallCount = 0
    var nowCallCount = 0

    let appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: { highlight },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/legacy.png") },
        setWallpaper: { _ in },
        fetchWallpaperTargets: {
            [
                (identifier: "display-1", pixelWidth: 1000, pixelHeight: 700, backingScaleFactor: 1.0),
                (identifier: "display-2", pixelWidth: 1200, pixelHeight: 800, backingScaleFactor: 1.0)
            ]
        },
        generateWallpapers: { _, _, _ in
            [
                (targetIdentifier: "display-1", fileURL: URL(fileURLWithPath: "/tmp/display-1.png"))
            ]
        },
        setWallpapers: { _ in
            setWallpapersCallCount += 1
        },
        markHighlightShown: { _ in
            markCallCount += 1
        },
        now: {
            nowCallCount += 1
            return Date(timeIntervalSince1970: 0)
        }
    )

    let didRotate = appState.rotateWallpaper()
    assertEqual(didRotate, false, "Expected rotateWallpaper to fail when generated wallpaper targets do not match fetched targets")
    assertEqual(setWallpapersCallCount, 0, "Expected per-screen apply to be skipped on identifier mismatch")
    assertEqual(markCallCount, 0, "Expected markHighlightShown to be skipped on identifier mismatch")
    assertEqual(nowCallCount, 0, "Expected timestamp update to be skipped on identifier mismatch")
}

func sampleHighlight(id: UUID = UUID(), quoteText: String) -> Highlight {
    Highlight(
        id: id,
        bookId: UUID(),
        quoteText: quoteText,
        bookTitle: "Book",
        author: "Author",
        location: nil,
        dateAdded: nil,
        lastShownAt: nil
    )
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertDateEqual(_ actual: Date?, _ expected: Date?, _ message: String) {
    switch (actual, expected) {
    case (nil, nil):
        return
    case let (lhs?, rhs?):
        let delta = abs(lhs.timeIntervalSince1970 - rhs.timeIntervalSince1970)
        if delta > 0.000_001 {
            fputs("Assertion failed: \(message). Expected \(rhs), got \(lhs)\n", stderr)
            exit(1)
        }
    default:
        fputs("Assertion failed: \(message). Expected \(String(describing: expected)), got \(String(describing: actual))\n", stderr)
        exit(1)
    }
}

struct Fixture {
    let defaults: UserDefaults
    let suiteName: String

    static func make() throws -> Fixture {
        let suiteName = "KindleWall-T24-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "VerifyT24",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create UserDefaults suite"]
            )
        }

        defaults.removePersistentDomain(forName: suiteName)
        return Fixture(defaults: defaults, suiteName: suiteName)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

do {
    try testLastChangedAtUserDefaultsHelperRoundTripsAndClears()
    try testLastChangedAtUserDefaultsHelperParsesLegacyFormats()
    try testAppStateInitLoadsPersistedLastChangedAt()
    try testRotateWallpaperHappyPathCallsInOrderAndUpdatesState()
    try testRotateWallpaperSkipsWorkWhenNoHighlightIsAvailable()
    try testRotateWallpaperPassesNilBackgroundToGenerator()
    try testRotateWallpaperReentrancyGuardPreventsNestedWork()
    try testRotateWallpaperUsesPerScreenPipelineWhenConfigured()
    try testRotateWallpaperPerScreenPipelineRejectsIdentifierMismatch()
    print("T24 verification passed")
} catch {
    fputs("Verification failure: \(error)\n", stderr)
    exit(1)
}
SWIFT

swiftc \
  -module-cache-path "$TMP_DIR/module-cache" \
  "$ROOT_DIR/App/ScheduleSettings.swift" \
  "$ROOT_DIR/App/AppState.swift" \
  "$ROOT_DIR/Models/Highlight.swift" \
  "$ROOT_DIR/Models/Book.swift" \
  "$TMP_DIR/main.swift" \
  -o "$TMP_DIR/t24_runner"

"$TMP_DIR/t24_runner"
