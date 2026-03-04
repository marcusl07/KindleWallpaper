import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject private var navigationModel: SettingsNavigationModel
    @State private var backgroundImageError: String? = nil
    @State private var backgroundCollectionCount: Int = 0
    @State private var primaryBackgroundName: String = "No image selected"

    init(navigationModel: SettingsNavigationModel) {
        _navigationModel = ObservedObject(wrappedValue: navigationModel)
    }

    var body: some View {
        NavigationStack(path: $navigationModel.path) {
            Form {
                quotesSection
                booksSection
                backgroundSection
                scheduleSection
                displaySection
                aboutSection
            }
            .formStyle(.grouped)
            .navigationTitle("Settings")
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                case .quotes:
                    QuotesListView()
                        .navigationTitle("Quotes")
                case .books:
                    BooksListView()
                        .navigationTitle("Books")
                case .backgrounds:
                    BackgroundsListView()
                        .navigationTitle("Backgrounds")
                }
            }
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshBackgroundSummary()
        }
        .onReceive(NotificationCenter.default.publisher(for: .kindleWallBackgroundCollectionDidChange)) { _ in
            refreshBackgroundSummary()
        }
    }

    private var quotesSection: some View {
        Section("Quotes") {
            settingsNavigationButton(
                title: "Quotes",
                subtitle: quoteLibrarySummary,
                destination: .quotes
            )
        }
    }

    private var booksSection: some View {
        Section("Books") {
            settingsNavigationButton(
                title: "Manage Books",
                subtitle: "\(enabledBookCount) of \(appState.books.count) books enabled",
                destination: .books
            )
        }
    }

    private var backgroundSection: some View {
        Section("Backgrounds") {
            settingsNavigationButton(
                title: "Show Backgrounds",
                subtitle: "\(backgroundCollectionCount) \(backgroundCollectionCount == 1 ? "image" : "images") • Current selection: \(primaryBackgroundName)",
                destination: .backgrounds
            )

            if let backgroundImageError {
                settingsMessageRow(backgroundImageError, tone: .error)
            }
        }
    }

    private var scheduleSection: some View {
        Section("Rotation Schedule") {
            Picker("Change wallpaper:", selection: scheduleModeBinding) {
                Text("Manual only")
                    .tag(RotationScheduleMode.manual)
                Text("Daily at set time")
                    .tag(RotationScheduleMode.daily)
                Text("On app launch")
                    .tag(RotationScheduleMode.onLaunch)
                Text("Every 30 minutes")
                    .tag(RotationScheduleMode.every30Minutes)
            }
            #if canImport(AppKit)
            .pickerStyle(.radioGroup)
            #endif

            if appState.activeScheduleMode == .daily {
                DatePicker(
                    "Daily time:",
                    selection: dailyScheduleTimeBinding,
                    displayedComponents: .hourAndMinute
                )
                #if canImport(AppKit)
                .datePickerStyle(.field)
                #endif
            }

            settingsMessageRow("Last changed: \(formattedLastChangedAt)")
            settingsMessageRow("Timed rotation requires the app to be running.", tone: .secondary)
            settingsMessageRow(
                "To avoid conflicts, disable macOS wallpaper rotation in System Settings > Wallpaper.",
                tone: .secondary
            )
        }
    }

    private var aboutSection: some View {
        Section("About") {
            settingsValueRow(label: "App", value: "KindleWall")
            settingsValueRow(label: "Version", value: appVersionDisplay)
        }
    }

    private var displaySection: some View {
        Section("Display") {
            Toggle("Capitalize first letter of highlight text", isOn: capitalizeHighlightTextBinding)
            settingsMessageRow(
                "If a quote starts lowercase, KindleWall displays it with an uppercase first letter.",
                tone: .secondary
            )
        }
    }

    private func refreshBackgroundSummary() {
        let state = appState.loadBackgroundCollectionState()
        backgroundCollectionCount = state.items.count
        primaryBackgroundName = state.items.first(where: { $0.id == state.selectedItemID })?.fileURL.deletingPathExtension().lastPathComponent ?? "No image selected"
        backgroundImageError = state.warningMessage
    }

    private var scheduleModeBinding: Binding<RotationScheduleMode> {
        Binding(
            get: {
                appState.activeScheduleMode
            },
            set: { newMode in
                appState.setActiveScheduleMode(newMode)
            }
        )
    }

    private var dailyScheduleTimeBinding: Binding<Date> {
        Binding(
            get: {
                timeOnlyDate(
                    hour: UserDefaults.standard.scheduleDailyHour,
                    minute: UserDefaults.standard.scheduleDailyMinute
                )
            },
            set: { newValue in
                let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
                UserDefaults.standard.scheduleDailyHour = components.hour ?? 9
                UserDefaults.standard.scheduleDailyMinute = components.minute ?? 0
            }
        )
    }

    private var capitalizeHighlightTextBinding: Binding<Bool> {
        Binding(
            get: {
                appState.capitalizeHighlightText
            },
            set: { enabled in
                appState.setCapitalizeHighlightText(enabled)
            }
        )
    }

    private var formattedLastChangedAt: String {
        guard let lastChangedAt = appState.lastChangedAt else {
            return "Never"
        }
        return lastChangedAt.formatted(date: .abbreviated, time: .shortened)
    }

    private var appVersionDisplay: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let shortVersion = info["CFBundleShortVersionString"] as? String
        let buildVersion = info["CFBundleVersion"] as? String

        switch (shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines), buildVersion?.trimmingCharacters(in: .whitespacesAndNewlines)) {
        case let (short?, build?) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (short?, _) where !short.isEmpty:
            return short
        case let (_, build?) where !build.isEmpty:
            return build
        default:
            return "Unknown"
        }
    }

    private func timeOnlyDate(hour: Int, minute: Int) -> Date {
        let clampedHour = min(max(hour, 0), 23)
        let clampedMinute = min(max(minute, 0), 59)
        let calendar = Calendar.current
        var components = calendar.dateComponents([.year, .month, .day], from: Date())
        components.hour = clampedHour
        components.minute = clampedMinute
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }

    private var enabledBookCount: Int {
        appState.books.filter(\.isEnabled).count
    }

    private var quoteLibrarySummary: String {
        "\(appState.totalHighlightCount) \(appState.totalHighlightCount == 1 ? "highlight" : "highlights") in library"
    }

    private func settingsNavigationRow(title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.callout.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private func settingsNavigationButton(title: String, subtitle: String, destination: SettingsDestination) -> some View {
        Button {
            navigationModel.path.append(destination)
        } label: {
            settingsNavigationRow(title: title, subtitle: subtitle)
        }
        .buttonStyle(.plain)
    }

    private func settingsMessageRow(_ message: String, tone: SettingsMessageTone = .primary) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(tone.color)
    }

    private func settingsValueRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
            Spacer(minLength: 12)
            Text(value)
                .foregroundStyle(.secondary)
        }
    }
}

enum SettingsDestination: Hashable {
    case quotes
    case books
    case backgrounds
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    @Published var path: [SettingsDestination] = [] {
        didSet {
            guard !isPerformingProgrammaticNavigation else {
                recalculateAvailability()
                return
            }

            if path.count > oldValue.count {
                forwardStack.removeAll()
            } else if path.isEmpty && !oldValue.isEmpty && oldValue != path {
                forwardStack = Array(oldValue.reversed())
            }

            recalculateAvailability()
        }
    }

    @Published private(set) var canGoBack = false
    @Published private(set) var canGoForward = false

    private var forwardStack: [SettingsDestination] = []
    private var isPerformingProgrammaticNavigation = false

    func goBack() {
        var poppedDestination: SettingsDestination?

        mutatePath {
            poppedDestination = path.popLast()
        }

        guard let poppedDestination else {
            return
        }

        forwardStack.append(poppedDestination)
        recalculateAvailability()
    }

    func goForward() {
        guard let destination = forwardStack.popLast() else {
            return
        }

        mutatePath {
            path.append(destination)
        }
    }

    private func mutatePath(_ mutation: () -> Void) {
        isPerformingProgrammaticNavigation = true
        mutation()
        isPerformingProgrammaticNavigation = false
        recalculateAvailability()
    }

    private func recalculateAvailability() {
        canGoBack = !path.isEmpty
        canGoForward = !forwardStack.isEmpty
    }
}

#if TESTING
@MainActor
struct SettingsNavigationModelTestProbe {
    private let navigationModel = SettingsNavigationModel()

    func goBack() {
        navigationModel.goBack()
    }

    func goForward() {
        navigationModel.goForward()
    }

    func push(_ destination: SettingsDestination) {
        navigationModel.path.append(destination)
    }

    var path: [SettingsDestination] {
        navigationModel.path
    }

    var canGoBack: Bool {
        navigationModel.canGoBack
    }

    var canGoForward: Bool {
        navigationModel.canGoForward
    }
}
#endif

private enum SettingsMessageTone {
    case primary
    case secondary
    case error

    var color: AnyShapeStyle {
        switch self {
        case .primary:
            AnyShapeStyle(.primary)
        case .secondary:
            AnyShapeStyle(.secondary)
        case .error:
            AnyShapeStyle(.red)
        }
    }
}

enum QuotesListSortMode: String, CaseIterable, Identifiable {
    case mostRecentlyAdded
    case alphabeticalByBook

    var id: Self { self }

    var title: String {
        switch self {
        case .mostRecentlyAdded:
            return "Most Recent"
        case .alphabeticalByBook:
            return "Book A-Z"
        }
    }
}

private enum QuotesListPresentationModel {
    static func displayedHighlights(
        from highlights: [Highlight],
        searchText: String,
        sortMode: QuotesListSortMode
    ) -> [Highlight] {
        highlights
            .filter { matchesSearch($0, searchText: searchText) }
            .sorted { lhs, rhs in
                switch sortMode {
                case .mostRecentlyAdded:
                    return compareByMostRecent(lhs, rhs)
                case .alphabeticalByBook:
                    return compareAlphabetically(lhs, rhs)
                }
            }
    }

    static func previewText(for quoteText: String) -> String {
        let collapsedWhitespace = quoteText.replacingOccurrences(
            of: #"\s+"#,
            with: " ",
            options: .regularExpression
        )
        let trimmed = collapsedWhitespace.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled quote" : trimmed
    }

    static func bookTitleText(for highlight: Highlight) -> String {
        fallbackText(from: highlight.bookTitle, placeholder: "Unknown Book")
    }

    static func authorText(for highlight: Highlight) -> String {
        fallbackText(from: highlight.author, placeholder: "Unknown Author")
    }

    private static func matchesSearch(_ highlight: Highlight, searchText: String) -> Bool {
        let trimmedSearchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearchText.isEmpty else {
            return true
        }

        let searchableFields = [
            previewText(for: highlight.quoteText),
            bookTitleText(for: highlight),
            authorText(for: highlight)
        ]

        return searchableFields.contains { field in
            field.localizedCaseInsensitiveContains(trimmedSearchText)
        }
    }

    private static func compareByMostRecent(_ lhs: Highlight, _ rhs: Highlight) -> Bool {
        switch (lhs.dateAdded, rhs.dateAdded) {
        case let (lhsDate?, rhsDate?) where lhsDate != rhsDate:
            return lhsDate > rhsDate
        case (_?, nil):
            return true
        case (nil, _?):
            return false
        default:
            return compareAlphabetically(lhs, rhs)
        }
    }

    private static func compareAlphabetically(_ lhs: Highlight, _ rhs: Highlight) -> Bool {
        let lhsKey = [
            bookTitleText(for: lhs),
            authorText(for: lhs),
            previewText(for: lhs.quoteText)
        ]
        let rhsKey = [
            bookTitleText(for: rhs),
            authorText(for: rhs),
            previewText(for: rhs.quoteText)
        ]

        for (lhsValue, rhsValue) in zip(lhsKey, rhsKey) where lhsValue.caseInsensitiveCompare(rhsValue) != .orderedSame {
            return lhsValue.localizedCaseInsensitiveCompare(rhsValue) == .orderedAscending
        }

        return lhs.id.uuidString < rhs.id.uuidString
    }

    private static func fallbackText(from rawValue: String, placeholder: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? placeholder : trimmed
    }
}

private struct QuotesListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var sortMode: QuotesListSortMode = .mostRecentlyAdded
    @State private var highlights: [Highlight] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            QuotesImportHeaderView()

            controlsRow

            Group {
                if highlights.isEmpty {
                    ContentUnavailableView(
                        "No Quotes Yet",
                        systemImage: "quote.opening",
                        description: Text("Import `My Clippings.txt` to build your quote library.")
                    )
                } else if displayedHighlights.isEmpty {
                    ContentUnavailableView(
                        "No Matching Quotes",
                        systemImage: "magnifyingglass",
                        description: Text("Try a different search term or switch the sort.")
                    )
                } else {
                    List(displayedHighlights) { highlight in
                        quoteRow(highlight)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .searchable(text: $searchText, prompt: "Search quotes, books, or authors")
        .onAppear(perform: refreshHighlights)
        .onReceive(appState.$totalHighlightCount) { _ in
            refreshHighlights()
        }
    }

    private var displayedHighlights: [Highlight] {
        QuotesListPresentationModel.displayedHighlights(
            from: highlights,
            searchText: searchText,
            sortMode: sortMode
        )
    }

    private var controlsRow: some View {
        HStack(alignment: .center, spacing: 12) {
            Picker("Sort", selection: $sortMode) {
                ForEach(QuotesListSortMode.allCases) { mode in
                    Text(mode.title)
                        .tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 280)

            Spacer(minLength: 12)

            Text(resultCountSummary)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var resultCountSummary: String {
        if highlights.isEmpty {
            return "0 quotes"
        }

        let displayedCount = displayedHighlights.count
        let noun = displayedCount == 1 ? "quote" : "quotes"

        if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "\(displayedCount) \(noun)"
        }

        return "\(displayedCount) of \(highlights.count) \(highlights.count == 1 ? "quote" : "quotes")"
    }

    private func quoteRow(_ highlight: Highlight) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(QuotesListPresentationModel.previewText(for: highlight.quoteText))
                .font(.body)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(QuotesListPresentationModel.bookTitleText(for: highlight))
                    .font(.callout.weight(.medium))
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(QuotesListPresentationModel.authorText(for: highlight))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }

    private func refreshHighlights() {
        highlights = appState.loadAllHighlights()
    }
}

#if TESTING
enum QuotesListViewTestProbe {
    static func displayedHighlightIDs(
        from highlights: [Highlight],
        searchText: String,
        sortMode: QuotesListSortMode
    ) -> [UUID] {
        QuotesListPresentationModel.displayedHighlights(
            from: highlights,
            searchText: searchText,
            sortMode: sortMode
        ).map(\.id)
    }

    static func previewText(for quoteText: String) -> String {
        QuotesListPresentationModel.previewText(for: quoteText)
    }

    static func bookTitleText(for highlight: Highlight) -> String {
        QuotesListPresentationModel.bookTitleText(for: highlight)
    }

    static func authorText(for highlight: Highlight) -> String {
        QuotesListPresentationModel.authorText(for: highlight)
    }
}
#endif

private struct QuotesImportHeaderView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Button("Import My Clippings.txt...") {
                    chooseClippingsFile(for: appState)
                }

                Spacer(minLength: 8)

                Text("\(appState.totalHighlightCount) \(appState.totalHighlightCount == 1 ? "highlight" : "highlights") in library")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            if let importError = appState.importError, !importError.isEmpty {
                settingsMessageRow(importError, tone: .error)
            } else if !appState.importStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                settingsMessageRow(appState.importStatus)
            } else {
                settingsMessageRow("No imports yet.", tone: .secondary)
            }
        }
    }

    private func settingsMessageRow(_ message: String, tone: SettingsMessageTone = .primary) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(tone.color)
    }
}

@MainActor
private func chooseClippingsFile(for appState: AppState) {
    #if canImport(AppKit)
    let panel = NSOpenPanel()
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    if let txtType = UTType(filenameExtension: "txt") {
        panel.allowedContentTypes = [txtType]
    } else {
        panel.allowedContentTypes = [.plainText]
    }
    panel.title = "Import My Clippings.txt"
    panel.prompt = "Import"

    guard panel.runModal() == .OK, let selectedURL = panel.url else {
        return
    }

    importClippingsFile(at: selectedURL, for: appState)
    #endif
}

@MainActor
private func importClippingsFile(at fileURL: URL, for appState: AppState) {
    #if canImport(GRDB)
    let result = importFile(at: fileURL)
    let status = VolumeWatcher.makeImportStatus(
        from: VolumeWatcher.ImportPayload(
            newHighlightCount: result.newHighlightCount,
            error: result.error,
            parseWarningCount: result.parseWarningCount
        ),
        now: Date()
    )
    appState.setImportStatus(status.message, isError: status.isError)
    appState.refreshLibraryState()
    #else
    appState.setImportStatus("Import unavailable in this build.", isError: true)
    #endif
}

enum BackgroundsWindowPresentation {
    static func requestShowWindow(notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .kindleWallShowBackgroundsWindow, object: nil)
    }

    static func notifyCollectionChanged(notificationCenter: NotificationCenter = .default) {
        notificationCenter.post(name: .kindleWallBackgroundCollectionDidChange, object: nil)
    }
}

extension Notification.Name {
    static let kindleWallShowBackgroundsWindow = Notification.Name("kindleWallShowBackgroundsWindow")
    static let kindleWallBackgroundCollectionDidChange = Notification.Name("kindleWallBackgroundCollectionDidChange")
}

struct BooksListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Button("Select All") {
                    appState.setAllBooksEnabled(true)
                }
                .disabled(
                    appState.isBookMutationInFlight ||
                    appState.books.isEmpty ||
                    appState.books.allSatisfy(\.isEnabled)
                )

                Button("Deselect All") {
                    appState.setAllBooksEnabled(false)
                }
                .disabled(
                    appState.isBookMutationInFlight ||
                    appState.books.isEmpty ||
                    appState.books.allSatisfy { !$0.isEnabled }
                )
            }

            List {
                if appState.books.isEmpty {
                    Text("No books imported yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appState.books) { book in
                        bookRow(book)
                    }
                }
            }
            .listStyle(.inset)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if allBooksDeselectedWarningVisible {
                Text("All books are deselected. Wallpaper rotation has no active quote pool.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var allBooksDeselectedWarningVisible: Bool {
        !appState.books.isEmpty && appState.books.allSatisfy { !$0.isEnabled }
    }

    private func bookRow(_ book: Book) -> some View {
        Toggle(isOn: bindingForBook(book)) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(book.title)
                    .font(.body.weight(.medium))
                Text(book.author)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text("\(book.highlightCount) \(book.highlightCount == 1 ? "highlight" : "highlights")")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .toggleStyle(.checkbox)
        .disabled(appState.isBookMutationInFlight)
    }

    private func bindingForBook(_ book: Book) -> Binding<Bool> {
        Binding(
            get: {
                appState.books.first(where: { $0.id == book.id })?.isEnabled ?? false
            },
            set: { enabled in
                let currentEnabled = appState.books.first(where: { $0.id == book.id })?.isEnabled ?? false
                guard currentEnabled != enabled else {
                    return
                }
                appState.setBookEnabled(id: book.id, enabled: enabled)
            }
        )
    }
}

struct BackgroundsListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var collectionState = AppState.BackgroundCollectionState(items: [], selectedItemID: nil, warningMessage: nil)
    @State private var selectedBackgroundID: UUID? = nil
    @State private var operationError: String? = nil

    private let gridColumns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Backgrounds")
                .font(.headline)

            controlsRow

            if let warningMessage = collectionState.warningMessage {
                Text(warningMessage)
                    .font(.callout)
                    .foregroundStyle(.orange)
            }

            if let operationError {
                Text(operationError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            if collectionState.items.isEmpty {
                emptyStateCard
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            } else {
                ScrollView {
                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 12) {
                        ForEach(collectionState.items) { item in
                            tile(for: item)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear {
            refreshCollection()
        }
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button("Add Photo...") {
                choosePhotos()
            }

            Button("Add Folder...") {
                chooseFolder()
            }

            Button("Remove Selected") {
                removeSelected()
            }
            .disabled(!canRemoveSelected)

            Spacer(minLength: 8)

            Text("\(collectionState.items.count) \(collectionState.items.count == 1 ? "item" : "items")")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var emptyStateCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No background images yet.")
                .font(.headline)
            Text("Add at least one background image to start rotating wallpapers.")
                .font(.callout)
                .foregroundStyle(.secondary)
            Button("Add Photo...") {
                choosePhotos()
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.black.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.black.opacity(0.10), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
        )
    }

    private func tile(for item: AppState.BackgroundCollectionItem) -> some View {
        let isSelected = selectedBackgroundID == item.id

        return Button {
            setSelected(item.id)
        } label: {
            tileCardLabel(for: item, isSelected: isSelected)
        }
        .buttonStyle(.plain)
    }

    private func tileCardLabel(for item: AppState.BackgroundCollectionItem, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            tilePreview(for: item.fileURL)
                .frame(height: 110)
            Text(item.fileURL.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.primary)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.black.opacity(0.12), lineWidth: isSelected ? 2 : 1)
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.accentColor)
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private func tilePreview(for fileURL: URL) -> some View {
        #if canImport(AppKit)
        if let image = BackgroundImageLoader.shared.load(from: fileURL).image {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            fallbackPreview
        }
        #else
        fallbackPreview
        #endif
    }

    private var fallbackPreview: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black)
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            )
    }

    private var canRemoveSelected: Bool {
        selectedBackgroundID != nil && collectionState.items.count > 1
    }

    private func refreshCollection() {
        collectionState = appState.loadBackgroundCollectionState()
        selectedBackgroundID = collectionState.selectedItemID ?? collectionState.items.first?.id
    }

    private func setSelected(_ id: UUID) {
        do {
            try appState.setPrimaryBackgroundImageSelection(id: id)
            operationError = nil
            refreshCollection()
            selectedBackgroundID = id
            BackgroundsWindowPresentation.notifyCollectionChanged()
        } catch {
            operationError = "Failed to select background: \(error.localizedDescription)"
        }
    }

    private func removeSelected() {
        guard let selectedBackgroundID else {
            return
        }

        do {
            try appState.removeBackgroundImageSelection(id: selectedBackgroundID)
            operationError = nil
            refreshCollection()
            BackgroundsWindowPresentation.notifyCollectionChanged()
        } catch {
            operationError = "Failed to remove background: \(error.localizedDescription)"
        }
    }

    private func addBackgroundURLs(_ sourceURLs: [URL]) {
        guard !sourceURLs.isEmpty else {
            return
        }

        var successfulAdds = 0
        var firstError: Error?

        for sourceURL in sourceURLs {
            do {
                try appState.addBackgroundImageSelection(from: sourceURL)
                successfulAdds += 1
            } catch {
                if firstError == nil {
                    firstError = error
                }
            }
        }

        refreshCollection()
        if successfulAdds > 0 {
            operationError = nil
            BackgroundsWindowPresentation.notifyCollectionChanged()
        } else if let firstError {
            operationError = "Failed to add background: \(firstError.localizedDescription)"
        }
    }

    private func choosePhotos() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.jpeg, .png, .heic]
        panel.title = "Add Background Photos"
        panel.prompt = "Add"

        guard panel.runModal() == .OK else {
            return
        }

        addBackgroundURLs(panel.urls)
        #endif
    }

    private func chooseFolder() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Add Background Folder"
        panel.prompt = "Add Folder"

        guard panel.runModal() == .OK, let folderURL = panel.url else {
            return
        }

        let supportedExtensions = Set(["jpg", "jpeg", "png", "heic", "heif"])
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let enumerator = FileManager.default.enumerator(
            at: folderURL,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )

        var fileURLs: [URL] = []
        while let next = enumerator?.nextObject() as? URL {
            let values = try? next.resourceValues(forKeys: Set(keys))
            guard values?.isRegularFile == true else {
                continue
            }
            let fileExtension = next.pathExtension.lowercased()
            if supportedExtensions.contains(fileExtension) {
                fileURLs.append(next)
            }
        }

        fileURLs.sort {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }

        if fileURLs.isEmpty {
            operationError = "No supported image files found in selected folder."
            return
        }
        addBackgroundURLs(fileURLs)
        #endif
    }
}
