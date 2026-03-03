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
private func testStoreSelectionPreservesCollectionOrder() throws {
    let fixture = try Fixture.make()
    defer { fixture.cleanup() }

    let firstURL = fixture.rootURL.appendingPathComponent("first.png")
    let secondURL = fixture.rootURL.appendingPathComponent("second.png")
    let thirdURL = fixture.rootURL.appendingPathComponent("third.png")
    try Data("first".utf8).write(to: firstURL, options: .atomic)
    try Data("second".utf8).write(to: secondURL, options: .atomic)
    try Data("third".utf8).write(to: thirdURL, options: .atomic)

    let store = makeStore(from: fixture)
    let firstStoredURL = try store.saveBackgroundImage(from: firstURL)
    let secondItem = try store.addBackgroundImage(from: secondURL)

    let initial = store.loadBackgroundImageCollection()
    expect(initial.items.count == 2, "Expected two items after save+add")
    expect(initial.items[0].id != initial.items[1].id, "Expected distinct collection item identities")
    let initialOrder = initial.items.map(\.id)
    expect(
        initial.selectedItemID == initial.items.first?.id,
        "Expected initial selection to default to the first item"
    )
    expect(
        store.loadBackgroundImageURL()?.standardizedFileURL == firstStoredURL.standardizedFileURL,
        "Expected single-image loader to resolve the selected background image"
    )

    _ = try store.promoteBackgroundImage(id: secondItem.id)
    let promoted = store.loadBackgroundImageCollection()
    expect(promoted.items.map(\.id) == initialOrder, "Expected selecting an item to preserve collection order")
    expect(promoted.selectedItemID == secondItem.id, "Expected selected item identity to update without reordering")
    expect(
        store.loadBackgroundImageURL()?.lastPathComponent == secondItem.fileURL.lastPathComponent,
        "Expected selected image lookup to track the explicit selection"
    )

    let appState = AppState(
        userDefaults: fixture.defaults,
        pickNextHighlight: { nil },
        loadBackgroundImageURLs: store.loadBackgroundImageURLs,
        generateWallpaper: { _, _ in
            URL(fileURLWithPath: "/tmp/verify_t57_unused.png")
        },
        setWallpaper: { _ in },
        markHighlightShown: { _ in },
        loadBackgroundPreviewState: {
            let result = store.loadBackgroundImageCollection()
            return AppState.BackgroundPreviewState(
                primaryImageURL: result.items.first(where: { $0.id == result.selectedItemID })?.fileURL,
                warningMessage: nil
            )
        },
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
                selectedItemID: result.selectedItemID,
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
    expect(state.selectedItemID == secondItem.id, "Expected AppState to surface the selected background id")
    let idsBeforeAdd = Set(state.items.map { $0.id })
    let orderBeforeAdd = state.items.map { $0.id }

    try appState.addBackgroundImageSelection(from: thirdURL)
    state = appState.loadBackgroundCollectionState()
    expect(state.items.count == 3, "Expected AppState add boundary to append item")
    expect(state.items.prefix(2).map { $0.id } == orderBeforeAdd, "Expected add boundary to preserve existing order")

    guard let thirdID = state.items.first(where: { !idsBeforeAdd.contains($0.id) })?.id else {
        fail("Expected to find third image id in AppState collection")
    }
    try appState.setPrimaryBackgroundImageSelection(id: thirdID)
    state = appState.loadBackgroundCollectionState()
    expect(state.selectedItemID == thirdID, "Expected AppState primary-selection boundary to update selected id")
    expect(state.items.prefix(2).map { $0.id } == orderBeforeAdd, "Expected AppState selection boundary to keep prior item order")

    try appState.removeBackgroundImageSelection(id: thirdID)
    state = appState.loadBackgroundCollectionState()
    expect(state.items.count == 2, "Expected AppState remove boundary to remove selected item")
    expect(state.selectedItemID == orderBeforeAdd.first, "Expected selected item to fall back to the first remaining item")

    let firstRemaining = state.items[0].id
    let secondRemaining = state.items[1].id
    try appState.removeBackgroundImageSelection(id: firstRemaining)
    let singleRemainingState = appState.loadBackgroundCollectionState()
    expect(singleRemainingState.items.count == 1, "Expected one item remaining after second remove")
    expect(singleRemainingState.selectedItemID == secondRemaining, "Expected final remaining image to become selected")

    expectThrows("Expected removing the final background image to throw") {
        try appState.removeBackgroundImageSelection(id: secondRemaining)
    }
}

@MainActor
func runVerifyT57() throws {
    try testStoreSelectionPreservesCollectionOrder()
    print("verify_t57_main passed")
}

try await MainActor.run {
    try runVerifyT57()
}
