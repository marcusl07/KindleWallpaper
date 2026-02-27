import Foundation

private func fail(_ message: String) -> Never {
    fputs("verify_t57_main failed: \(message)\n", stderr)
    exit(1)
}

private func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    if !condition() {
        fail(message)
    }
}

private func expectThrows(_ message: String, _ block: () throws -> Void) {
    do {
        try block()
        fail(message)
    } catch {
        // Expected
    }
}

private struct Fixture {
    let rootURL: URL
    let appSupportURL: URL
    let defaults: UserDefaults
    let defaultsSuiteName: String

    static func make() throws -> Fixture {
        let fm = FileManager.default
        let rootURL = fm.temporaryDirectory.appendingPathComponent("kindlewall-t57-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: rootURL, withIntermediateDirectories: true)

        let appSupportURL = rootURL.appendingPathComponent("ApplicationSupport/KindleWall", isDirectory: true)
        let suiteName = "verify_t57.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            throw NSError(
                domain: "verify_t57",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not create UserDefaults suite"]
            )
        }
        defaults.removePersistentDomain(forName: suiteName)

        return Fixture(
            rootURL: rootURL,
            appSupportURL: appSupportURL,
            defaults: defaults,
            defaultsSuiteName: suiteName
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: defaultsSuiteName)
        try? FileManager.default.removeItem(at: rootURL)
    }
}

private func makeStore(from fixture: Fixture) -> BackgroundImageStore {
    BackgroundImageStore(
        fileManager: .default,
        userDefaults: fixture.defaults,
        appSupportDirectoryURL: fixture.appSupportURL
    )
}

@MainActor
private func testStorePromotionAndAppStateCollectionBoundaries() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let firstURL = fixture.rootURL.appendingPathComponent("first.png")
    let secondURL = fixture.rootURL.appendingPathComponent("second.png")
    let thirdURL = fixture.rootURL.appendingPathComponent("third.png")
    try Data("first".utf8).write(to: firstURL, options: .atomic)
    try Data("second".utf8).write(to: secondURL, options: .atomic)
    try Data("third".utf8).write(to: thirdURL, options: .atomic)

    let store = makeStore(from: fixture)
    _ = try store.saveBackgroundImage(from: firstURL)
    let secondItem = try store.addBackgroundImage(from: secondURL)

    let initial = store.loadBackgroundImageCollection()
    expect(initial.items.count == 2, "Expected two items after save+add")
    expect(initial.items[0].id != initial.items[1].id, "Expected distinct collection item identities")

    _ = try store.promoteBackgroundImage(id: secondItem.id)
    let promoted = store.loadBackgroundImageCollection()
    expect(promoted.items.first?.id == secondItem.id, "Expected promoted item to be first in collection")

    let appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURLs: store.loadBackgroundImageURLs,
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/verify_t57_unused.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        loadBackgroundCollectionState: {
            let result = store.loadBackgroundImageCollection()
            return AppState.BackgroundCollectionState(
                items: result.items.map { item in
                    AppState.BackgroundCollectionItem(
                        id: item.id,
                        fileURL: item.fileURL,
                        addedAt: item.addedAt
                    )
                },
                warningMessage: nil
            )
        },
        addBackgroundImageSelection: { sourceURL in
            _ = try store.addBackgroundImage(from: sourceURL)
        },
        removeBackgroundImageSelection: { id in
            _ = try store.removeBackgroundImage(id: id)
        },
        setPrimaryBackgroundImageSelection: { id in
            _ = try store.promoteBackgroundImage(id: id)
        }
    )

    var state = appState.loadBackgroundCollectionState()
    expect(state.items.count == 2, "Expected AppState to load store-backed collection")
    let idsBeforeAdd = Set(state.items.map(\.id))

    try appState.addBackgroundImageSelection(from: thirdURL)
    state = appState.loadBackgroundCollectionState()
    expect(state.items.count == 3, "Expected AppState add boundary to append item")

    guard let thirdID = state.items.first(where: { !idsBeforeAdd.contains($0.id) })?.id else {
        fail("Expected to find third image id in AppState collection")
    }
    try appState.setPrimaryBackgroundImageSelection(id: thirdID)
    state = appState.loadBackgroundCollectionState()
    expect(state.items.first?.id == thirdID, "Expected AppState primary-selection boundary to reorder first item")

    try appState.removeBackgroundImageSelection(id: thirdID)
    state = appState.loadBackgroundCollectionState()
    expect(state.items.count == 2, "Expected AppState remove boundary to remove selected item")

    let firstRemaining = state.items[0].id
    let secondRemaining = state.items[1].id
    try appState.removeBackgroundImageSelection(id: firstRemaining)
    expect(appState.loadBackgroundCollectionState().items.count == 1, "Expected one item remaining after second remove")

    expectThrows("Expected removing the final background image to throw") {
        try appState.removeBackgroundImageSelection(id: secondRemaining)
    }
}

@MainActor
func runVerifyT57() throws {
    try testStorePromotionAndAppStateCollectionBoundaries()
    print("verify_t57_main passed")
}

try await MainActor.run {
    try runVerifyT57()
}
