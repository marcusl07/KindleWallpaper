#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TMP_DIR="$(mktemp -d /tmp/kindlewall_t27.XXXXXX)"
trap 'rm -rf "$TMP_DIR"' EXIT

cat > "$TMP_DIR/main.swift" <<'SWIFT'
import Foundation

func testInitLoadsDefaultsAndLibrarySnapshot() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    fixture.defaults.rotationScheduleMode = .every30Minutes
    let persistedLastChanged = Date(timeIntervalSince1970: 1_736_000_500)
    fixture.defaults.lastChangedAt = persistedLastChanged

    let expectedBooks = [
        Book(
            id: UUID(uuidString: "F5E25173-3478-447F-B333-EC0E438E31D5")!,
            title: "Book A",
            author: "Author A",
            isEnabled: true,
            highlightCount: 3
        ),
        Book(
            id: UUID(uuidString: "A0BC4DF6-1D5E-4E4A-9629-E638A78D7A89")!,
            title: "Book B",
            author: "Author B",
            isEnabled: false,
            highlightCount: 9
        )
    ]

    let appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        fetchAllBooks: { expectedBooks },
        fetchTotalHighlightCount: { 12 },
        now: { Date(timeIntervalSince1970: 0) }
    )

    assertEqual(appState.currentQuotePreview, "", "Expected empty quote preview by default")
    assertEqual(appState.importStatus, "", "Expected importStatus to default to empty string")
    assertEqual(appState.importError, nil, "Expected importError to default to nil")
    assertEqual(appState.totalHighlightCount, 12, "Expected totalHighlightCount to load from fetcher")
    assertBooksEqual(appState.books, expectedBooks, "Expected books to load from fetcher")
    assertEqual(
        appState.activeScheduleMode,
        .every30Minutes,
        "Expected activeScheduleMode to load from UserDefaults"
    )
    assertDateEqual(
        appState.lastChangedAt,
        persistedLastChanged,
        "Expected lastChangedAt to load from UserDefaults"
    )
}

func testSetImportStatusSeparatesSuccessAndErrorStates() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let appState = makeAppState(defaults: fixture.defaults)
    appState.setImportStatus("Library up to date", isError: false)

    assertEqual(appState.importStatus, "Library up to date", "Expected success status message to be stored")
    assertEqual(appState.importError, nil, "Expected success update to clear importError")

    appState.setImportStatus("  Import failed: unreadable file  ", isError: true)
    assertEqual(appState.importStatus, "", "Expected error update to clear importStatus")
    assertEqual(
        appState.importError,
        "Import failed: unreadable file",
        "Expected trimmed error message to be stored"
    )

    appState.setImportStatus("   ", isError: true)
    assertEqual(
        appState.importError,
        "Import failed: unknown error.",
        "Expected empty error message to normalize to default"
    )
}

func testRefreshLibraryStateReloadsBooksAndCount() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    var currentBooks = [
        Book(
            id: UUID(uuidString: "6DCD7F43-57AB-4873-9A02-FF7BF8A7A5CD")!,
            title: "Initial",
            author: "Author",
            isEnabled: true,
            highlightCount: 1
        )
    ]
    var currentCount = 1

    let appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        fetchAllBooks: { currentBooks },
        fetchTotalHighlightCount: { currentCount },
        now: { Date(timeIntervalSince1970: 0) }
    )

    currentBooks = [
        Book(
            id: UUID(uuidString: "6DCD7F43-57AB-4873-9A02-FF7BF8A7A5CD")!,
            title: "Initial",
            author: "Author",
            isEnabled: true,
            highlightCount: 2
        ),
        Book(
            id: UUID(uuidString: "A2D7E9A5-D8E2-4B78-ADE9-6CAEF09D4AF7")!,
            title: "Second",
            author: "Writer",
            isEnabled: true,
            highlightCount: 5
        )
    ]
    currentCount = 7

    appState.refreshLibraryState()
    assertEqual(appState.totalHighlightCount, 7, "Expected refreshLibraryState to reload total count")
    assertBooksEqual(appState.books, currentBooks, "Expected refreshLibraryState to reload books")
}

func testScheduleStateMethodsUpdateAndSyncUserDefaults() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    fixture.defaults.rotationScheduleMode = .daily
    let appState = makeAppState(defaults: fixture.defaults)
    assertEqual(appState.activeScheduleMode, .daily, "Expected initial schedule mode to match defaults")

    appState.setActiveScheduleMode(.manual)
    assertEqual(appState.activeScheduleMode, .manual, "Expected setActiveScheduleMode to update AppState")
    assertEqual(
        fixture.defaults.rotationScheduleMode,
        .manual,
        "Expected setActiveScheduleMode to persist to UserDefaults"
    )

    fixture.defaults.rotationScheduleMode = .onLaunch
    let nextTimestamp = Date(timeIntervalSince1970: 1_736_111_111)
    fixture.defaults.lastChangedAt = nextTimestamp
    appState.refreshScheduleState()

    assertEqual(
        appState.activeScheduleMode,
        .onLaunch,
        "Expected refreshScheduleState to reload mode from UserDefaults"
    )
    assertDateEqual(
        appState.lastChangedAt,
        nextTimestamp,
        "Expected refreshScheduleState to reload timestamp from UserDefaults"
    )
}

func testRefreshAllStateRefreshesLibraryAndScheduleTogether() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    var currentBooks = [
        Book(
            id: UUID(uuidString: "615B03D8-2E53-45BE-B271-2F5AE630612A")!,
            title: "One",
            author: "A",
            isEnabled: true,
            highlightCount: 2
        )
    ]
    var currentCount = 2

    let appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        fetchAllBooks: { currentBooks },
        fetchTotalHighlightCount: { currentCount },
        now: { Date(timeIntervalSince1970: 0) }
    )

    currentBooks = [
        Book(
            id: UUID(uuidString: "615B03D8-2E53-45BE-B271-2F5AE630612A")!,
            title: "One",
            author: "A",
            isEnabled: true,
            highlightCount: 2
        ),
        Book(
            id: UUID(uuidString: "A7ECA54D-9891-45C4-AAD6-B93AFC195F14")!,
            title: "Two",
            author: "B",
            isEnabled: false,
            highlightCount: 6
        )
    ]
    currentCount = 8
    fixture.defaults.rotationScheduleMode = .every30Minutes
    let refreshedLastChangedAt = Date(timeIntervalSince1970: 1_736_222_222)
    fixture.defaults.lastChangedAt = refreshedLastChangedAt

    appState.refreshAllState()

    assertEqual(appState.totalHighlightCount, 8, "Expected refreshAllState to refresh total count")
    assertBooksEqual(appState.books, currentBooks, "Expected refreshAllState to refresh books")
    assertEqual(
        appState.activeScheduleMode,
        .every30Minutes,
        "Expected refreshAllState to refresh schedule mode"
    )
    assertDateEqual(
        appState.lastChangedAt,
        refreshedLastChangedAt,
        "Expected refreshAllState to refresh lastChangedAt"
    )
}

func makeAppState(defaults: UserDefaults) -> AppState {
    AppState(
        userDefaults: defaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURL: { nil },
        generateWallpaper: { _, _ in URL(fileURLWithPath: "/tmp/unused.png") },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        now: { Date(timeIntervalSince1970: 0) }
    )
}

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String) {
    if actual != expected {
        fputs("Assertion failed: \(message). Expected \(expected), got \(actual)\n", stderr)
        exit(1)
    }
}

func assertBooksEqual(_ actual: [Book], _ expected: [Book], _ message: String) {
    guard actual.count == expected.count else {
        fputs("Assertion failed: \(message). Expected \(expected.count) books, got \(actual.count)\n", stderr)
        exit(1)
    }

    for index in 0..<expected.count {
        let lhs = actual[index]
        let rhs = expected[index]
        let matched = lhs.id == rhs.id
            && lhs.title == rhs.title
            && lhs.author == rhs.author
            && lhs.isEnabled == rhs.isEnabled
            && lhs.highlightCount == rhs.highlightCount
        if !matched {
            fputs("Assertion failed: \(message). Book mismatch at index \(index)\n", stderr)
            exit(1)
        }
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
        let suiteName = "KindleWall-T27-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "VerifyT27",
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
    try testInitLoadsDefaultsAndLibrarySnapshot()
    try testSetImportStatusSeparatesSuccessAndErrorStates()
    try testRefreshLibraryStateReloadsBooksAndCount()
    try testScheduleStateMethodsUpdateAndSyncUserDefaults()
    try testRefreshAllStateRefreshesLibraryAndScheduleTogether()
    print("T27 verification passed")
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
  -o "$TMP_DIR/t27_runner"

"$TMP_DIR/t27_runner"
