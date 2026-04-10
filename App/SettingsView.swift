import OSLog
import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    private static let intervalComponentFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .none
        formatter.minimum = 0
        formatter.maximumFractionDigits = 0
        formatter.usesGroupingSeparator = false
        return formatter
    }()

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
                case .quoteDetail(let highlightID):
                    if let highlight = appState.loadHighlight(id: highlightID) {
                        QuoteDetailView(highlight: highlight)
                            .navigationTitle("Quote")
                    } else {
                        QuotesEmptyStateView(
                            title: "Quote Not Found",
                            systemImage: "quote.opening",
                            description: "This quote is no longer available."
                        )
                        .navigationTitle("Quote")
                    }
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    navigationModel.goBack()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .help("Back")
                .disabled(!navigationModel.canGoBack)

                Button {
                    navigationModel.goForward()
                } label: {
                    Image(systemName: "chevron.right")
                }
                .help("Forward")
                .disabled(!navigationModel.canGoForward)
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
                Text("Every interval")
                    .tag(RotationScheduleMode.everyInterval)
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

            if appState.activeScheduleMode == .everyInterval {
                HStack(spacing: 8) {
                    Text("Every interval:")
                    TextField(
                        "",
                        value: scheduleIntervalHoursBinding,
                        formatter: Self.intervalComponentFormatter
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)

                    Text("hr")
                        .foregroundStyle(.secondary)

                    TextField(
                        "",
                        value: scheduleIntervalMinutesBinding,
                        formatter: Self.intervalComponentFormatter
                    )
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 56)

                    Text("min")
                        .foregroundStyle(.secondary)
                }
            }

            settingsMessageRow("Last changed: \(formattedLastChangedAt)")
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

    private var scheduleIntervalHoursBinding: Binding<Int> {
        Binding(
            get: {
                min(max(UserDefaults.standard.scheduleIntervalMinutes / 60, 0), 23)
            },
            set: { newHour in
                let clampedHour = min(max(newHour, 0), 23)
                let currentMinute = min(max(UserDefaults.standard.scheduleIntervalMinutes % 60, 0), 59)
                let resolvedMinute = clampedHour == 0 && currentMinute == 0 ? 1 : currentMinute
                UserDefaults.standard.scheduleIntervalMinutes = (clampedHour * 60) + resolvedMinute
            }
        )
    }

    private var scheduleIntervalMinutesBinding: Binding<Int> {
        Binding(
            get: {
                let storedMinutes = UserDefaults.standard.scheduleIntervalMinutes % 60
                if (UserDefaults.standard.scheduleIntervalMinutes / 60) == 0 && storedMinutes == 0 {
                    return 1
                }
                return storedMinutes
            },
            set: { newMinute in
                let currentHour = min(max(UserDefaults.standard.scheduleIntervalMinutes / 60, 0), 23)
                let clampedMinute = min(max(newMinute, 0), 59)
                let resolvedMinute = currentHour == 0 && clampedMinute == 0 ? 1 : clampedMinute
                UserDefaults.standard.scheduleIntervalMinutes = (currentHour * 60) + resolvedMinute
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
    case quoteDetail(UUID)
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

enum QuotesListBookStatusFilterMode: String, CaseIterable, Identifiable {
    case allBooks
    case enabledBooksOnly
    case disabledBooksOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .allBooks:
            return "All Books"
        case .enabledBooksOnly:
            return "Enabled Books"
        case .disabledBooksOnly:
            return "Disabled Books"
        }
    }
}

enum QuotesListSourceFilterMode: String, CaseIterable, Identifiable {
    case allQuotes
    case manualOnly

    var id: Self { self }

    var title: String {
        switch self {
        case .allQuotes:
            return "All Quotes"
        case .manualOnly:
            return "Manual Only"
        }
    }
}

struct QuotesListFilters: Equatable {
    var selectedBookTitle: String?
    var selectedAuthor: String?
    var bookStatus: QuotesListBookStatusFilterMode = .allBooks
    var source: QuotesListSourceFilterMode = .allQuotes

    var isActive: Bool {
        selectedBookTitle != nil ||
        selectedAuthor != nil ||
        bookStatus != .allBooks ||
        source != .allQuotes
    }
}

struct QuoteEditSaveRequest {
    let bookId: UUID?
    let quoteText: String
    let bookTitle: String
    let author: String
    let location: String?
}

private struct QuoteEditDraft {
    var quoteText: String
    var bookTitle: String
    var author: String
    var location: String

    init(
        quoteText: String,
        bookTitle: String,
        author: String,
        location: String
    ) {
        self.quoteText = quoteText
        self.bookTitle = bookTitle
        self.author = author
        self.location = location
    }

    init(highlight: Highlight?) {
        quoteText = highlight?.quoteText ?? ""
        bookTitle = highlight?.bookTitle ?? ""
        author = highlight?.author ?? ""
        location = highlight?.location ?? ""
    }
}

private enum QuoteEditPresentationModel {
    static func title(for highlight: Highlight?) -> String {
        highlight == nil ? "Add Quote" : "Edit Quote"
    }

    static func errorMessage(for error: AppState.QuoteSaveError) -> String {
        error.errorDescription ?? "Unable to save this quote."
    }

    static func errorRecoverySuggestion(for error: AppState.QuoteSaveError) -> String? {
        error.recoverySuggestion
    }

    static func canSave(quoteText: String) -> Bool {
        !trimmedValue(quoteText).isEmpty
    }

    static func matchedBook(
        bookTitle: String,
        author: String,
        books: [Book]
    ) -> Book? {
        guard
            let normalizedTitle = normalizedMatchValue(bookTitle),
            let normalizedAuthor = normalizedMatchValue(author)
        else {
            return nil
        }

        return books.first { book in
            normalizedMatchValue(book.title) == normalizedTitle &&
            normalizedMatchValue(book.author) == normalizedAuthor
        }
    }

    static func saveRequest(
        draft: QuoteEditDraft,
        books: [Book]
    ) -> QuoteEditSaveRequest {
        let trimmedQuoteText = trimmedValue(draft.quoteText)
        let trimmedLocation = trimmedOptionalValue(draft.location)

        if let matchedBook = matchedBook(
            bookTitle: draft.bookTitle,
            author: draft.author,
            books: books
        ) {
            return QuoteEditSaveRequest(
                bookId: matchedBook.id,
                quoteText: trimmedQuoteText,
                bookTitle: matchedBook.title,
                author: matchedBook.author,
                location: trimmedLocation
            )
        }

        return QuoteEditSaveRequest(
            bookId: nil,
            quoteText: trimmedQuoteText,
            bookTitle: trimmedValue(draft.bookTitle),
            author: trimmedValue(draft.author),
            location: trimmedLocation
        )
    }

    private static func normalizedMatchValue(_ rawValue: String) -> String? {
        let trimmed = trimmedValue(rawValue)
        guard !trimmed.isEmpty else {
            return nil
        }
        return trimmed.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }

    private static func trimmedValue(_ rawValue: String) -> String {
        rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimmedOptionalValue(_ rawValue: String) -> String? {
        let trimmed = trimmedValue(rawValue)
        return trimmed.isEmpty ? nil : trimmed
    }
}

private enum QuotesListPresentationModel {
    static func displayedHighlights(
        from highlights: [Highlight],
        searchText: String,
        filters: QuotesListFilters,
        bookEnabledByID: [UUID: Bool]
    ) -> [Highlight] {
        highlights
            .filter { matchesFilters($0, filters: filters, bookEnabledByID: bookEnabledByID) }
            .filter { matchesSearch($0, searchText: searchText) }
    }

    static func sortedHighlights(
        _ highlights: [Highlight],
        sortMode: QuotesListSortMode
    ) -> [Highlight] {
        highlights.sorted { lhs, rhs in
            switch sortMode {
            case .mostRecentlyAdded:
                return compareByMostRecent(lhs, rhs)
            case .alphabeticalByBook:
                return compareAlphabetically(lhs, rhs)
            }
        }
    }

    static func availableBookTitles(from highlights: [Highlight]) -> [String] {
        uniqueSortedValues(from: highlights.map(bookTitleText(for:)))
    }

    static func availableAuthors(from highlights: [Highlight]) -> [String] {
        uniqueSortedValues(from: highlights.map(authorText(for:)))
    }

    static func previewText(for quoteText: String) -> String {
        let collapsedWhitespace = collapseWhitespace(in: quoteText)
        return collapsedWhitespace.isEmpty ? "Untitled quote" : collapsedWhitespace
    }

    static func bookTitleText(for highlight: Highlight) -> String {
        fallbackText(from: highlight.bookTitle, placeholder: "Unknown Book")
    }

    static func authorText(for highlight: Highlight) -> String {
        fallbackText(from: highlight.author, placeholder: "Unknown Author")
    }

    private static func matchesFilters(
        _ highlight: Highlight,
        filters: QuotesListFilters,
        bookEnabledByID: [UUID: Bool]
    ) -> Bool {
        if let selectedBookTitle = filters.selectedBookTitle,
           bookTitleText(for: highlight) != selectedBookTitle {
            return false
        }

        if let selectedAuthor = filters.selectedAuthor,
           authorText(for: highlight) != selectedAuthor {
            return false
        }

        switch filters.source {
        case .allQuotes:
            break
        case .manualOnly:
            guard highlight.bookId == nil else {
                return false
            }
        }

        switch filters.bookStatus {
        case .allBooks:
            return true
        case .enabledBooksOnly:
            return bookEnabledState(for: highlight, bookEnabledByID: bookEnabledByID) == true
        case .disabledBooksOnly:
            return bookEnabledState(for: highlight, bookEnabledByID: bookEnabledByID) == false
        }
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

    private static func collapseWhitespace(in string: String) -> String {
        string.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func uniqueSortedValues(from values: [String]) -> [String] {
        let sortedValues = values.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }

        var dedupedValues: [String] = []
        dedupedValues.reserveCapacity(sortedValues.count)

        for value in sortedValues {
            if dedupedValues.last?.localizedCaseInsensitiveCompare(value) == .orderedSame {
                continue
            }
            dedupedValues.append(value)
        }

        return dedupedValues
    }

    private static func bookEnabledState(
        for highlight: Highlight,
        bookEnabledByID: [UUID: Bool]
    ) -> Bool? {
        guard let bookId = highlight.bookId else {
            return nil
        }

        return bookEnabledByID[bookId]
    }
}

private enum QuotesListPerformanceSignposts {
    private static let signposter = OSSignposter(
        subsystem: Bundle.main.bundleIdentifier ?? "com.marcuslo.KindleWall",
        category: .pointsOfInterest
    )

    static func beginRefresh(reason: String, sortMode: QuotesListSortMode) -> OSSignpostIntervalState {
        signposter.beginInterval(
            "QuotesListRefresh",
            "reason=\(reason, privacy: .public) sortMode=\(sortMode.rawValue, privacy: .public)"
        )
    }

    static func endRefresh(_ state: OSSignpostIntervalState, loadedCount: Int) {
        signposter.endInterval(
            "QuotesListRefresh",
            state,
            "rows=\(loadedCount)"
        )
    }

    static func cancelRefresh(_ state: OSSignpostIntervalState) {
        signposter.endInterval(
            "QuotesListRefresh",
            state,
            "cancelled=1"
        )
    }

    static func beginRender(reason: String, sortMode: QuotesListSortMode, totalCount: Int) -> OSSignpostIntervalState {
        signposter.beginInterval(
            "QuotesListRender",
            "reason=\(reason, privacy: .public) sortMode=\(sortMode.rawValue, privacy: .public) total=\(totalCount)"
        )
    }

    static func endRender(_ state: OSSignpostIntervalState, displayedCount: Int) {
        signposter.endInterval(
            "QuotesListRender",
            state,
            "displayed=\(displayedCount)"
        )
    }

    static func cancelRender(_ state: OSSignpostIntervalState) {
        signposter.endInterval(
            "QuotesListRender",
            state,
            "cancelled=1"
        )
    }
}

private struct QuotesListRenderCompletionObserver: NSViewRepresentable {
    let token: UUID
    let displayedCount: Int
    let onRendered: (UUID, Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        NSView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard context.coordinator.lastToken != token else {
            return
        }

        context.coordinator.lastToken = token
        DispatchQueue.main.async {
            onRendered(token, displayedCount)
        }
    }

    final class Coordinator {
        var lastToken: UUID?
    }
}

private struct QuotesListRowModel: Identifiable, Equatable {
    let highlight: Highlight
    let previewText: String
    let bookTitleText: String
    let authorText: String

    var id: UUID { highlight.id }

    init(highlight: Highlight) {
        self.highlight = highlight
        self.previewText = QuotesListPresentationModel.previewText(for: highlight.quoteText)
        self.bookTitleText = QuotesListPresentationModel.bookTitleText(for: highlight)
        self.authorText = QuotesListPresentationModel.authorText(for: highlight)
    }
}

private struct QuotesListRowView: View, Equatable {
    let row: QuotesListRowModel

    static func == (lhs: QuotesListRowView, rhs: QuotesListRowView) -> Bool {
        lhs.row == rhs.row
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(row.previewText)
                .font(.body)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(row.bookTitleText)
                    .font(.callout.weight(.medium))
                Text("•")
                    .foregroundStyle(.tertiary)
                Text(row.authorText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}

private enum QuotesListPagingConstants {
    static let pageSize = 100
    static let loadMoreThreshold = 20
}

private struct QuotesListRefreshResetState {
    let nextQueryGeneration: Int
    let isLoadingHighlights: Bool
    let isLoadingNextPage: Bool
    let hasMoreHighlights: Bool
    let highlights: [Highlight]
    let totalMatchingHighlightCount: Int
    let availableBookTitles: [String]
    let availableAuthors: [String]
    let selectedHighlightIDs: Set<UUID>
}

private struct QuotesListAppendPageResult {
    let highlights: [Highlight]
    let hasMoreHighlights: Bool
}

private enum QuotesListPagingPresentationModel {
    static func refreshResetState(after currentQueryGeneration: Int) -> QuotesListRefreshResetState {
        refreshResetState(
            after: currentQueryGeneration,
            preservingHighlights: [],
            totalMatchingHighlightCount: 0,
            availableBookTitles: [],
            availableAuthors: [],
            selectedHighlightIDs: []
        )
    }

    static func refreshResetState(
        after currentQueryGeneration: Int,
        preservingHighlights: [Highlight],
        totalMatchingHighlightCount: Int,
        availableBookTitles: [String],
        availableAuthors: [String],
        selectedHighlightIDs: Set<UUID>
    ) -> QuotesListRefreshResetState {
        QuotesListRefreshResetState(
            nextQueryGeneration: currentQueryGeneration + 1,
            isLoadingHighlights: true,
            isLoadingNextPage: false,
            hasMoreHighlights: false,
            highlights: preservingHighlights,
            totalMatchingHighlightCount: totalMatchingHighlightCount,
            availableBookTitles: availableBookTitles,
            availableAuthors: availableAuthors,
            selectedHighlightIDs: selectedHighlightIDs
        )
    }

    static func hasMoreHighlights(
        loadedCount: Int,
        totalMatchingHighlightCount: Int
    ) -> Bool {
        loadedCount < totalMatchingHighlightCount
    }

    static func shouldLoadMore(
        highlights: [Highlight],
        currentHighlightID: UUID,
        hasMoreHighlights: Bool,
        isLoadingHighlights: Bool,
        isLoadingNextPage: Bool,
        hasLoadMoreTask: Bool,
        loadMoreThreshold: Int = QuotesListPagingConstants.loadMoreThreshold
    ) -> Bool {
        guard
            hasMoreHighlights,
            !isLoadingHighlights,
            !isLoadingNextPage,
            !hasLoadMoreTask,
            let currentIndex = highlights.firstIndex(where: { $0.id == currentHighlightID })
        else {
            return false
        }

        let thresholdIndex = max(highlights.count - loadMoreThreshold, 0)
        return currentIndex >= thresholdIndex
    }

    static func appendPage(
        existingHighlights: [Highlight],
        nextPage: [Highlight],
        totalMatchingHighlightCount: Int
    ) -> QuotesListAppendPageResult {
        let existingHighlightIDs = Set(existingHighlights.map(\.id))
        let uniqueNextPage = nextPage.filter { !existingHighlightIDs.contains($0.id) }
        let mergedHighlights = existingHighlights + uniqueNextPage

        return QuotesListAppendPageResult(
            highlights: mergedHighlights,
            hasMoreHighlights: mergedHighlights.count < totalMatchingHighlightCount && !uniqueNextPage.isEmpty
        )
    }
}

private struct QuotesListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var searchText = ""
    @State private var sortMode: QuotesListSortMode = .mostRecentlyAdded
    @State private var filters = QuotesListFilters()
    @State private var highlights: [Highlight] = []
    @State private var rowModels: [QuotesListRowModel] = []
    @State private var totalMatchingHighlightCount = 0
    @State private var availableBookTitles: [String] = []
    @State private var availableAuthors: [String] = []
    @State private var selectedHighlightIDs: Set<UUID> = []
    @State private var pendingBulkDeleteHighlightIDs: [UUID] = []
    @State private var isEditingHighlights = false
    @State private var isPresentingAddQuote = false
    @State private var isLoadingHighlights = false
    @State private var isLoadingNextPage = false
    @State private var hasMoreHighlights = false
    @State private var queryGeneration = 0
    @State private var pendingRefreshSignpostState: OSSignpostIntervalState? = nil
    @State private var pendingRenderSignpostState: OSSignpostIntervalState? = nil
    @State private var renderObservationToken = UUID()
    @State private var refreshTask: Task<Void, Never>? = nil
    @State private var loadMoreTask: Task<Void, Never>? = nil

    var body: some View {
        let displayedRows = rowModels

        return VStack(alignment: .leading, spacing: 16) {
            if shouldShowImportHeader {
                QuotesImportHeaderView()
            }

            controlsRow(displayedCount: displayedRows.count)

            Group {
                if isLoadingHighlights {
                    ProgressView("Loading Quotes…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if appState.totalHighlightCount == 0 {
                    QuotesEmptyStateView(
                        title: "No Quotes Yet",
                        systemImage: "quote.opening",
                        description: "Import `My Clippings.txt` to build your quote library."
                    )
                } else if displayedRows.isEmpty {
                    QuotesEmptyStateView(
                        title: "No Matching Quotes",
                        systemImage: "magnifyingglass",
                        description: "Try a different search term or adjust the filters."
                    )
                } else if isEditingHighlights {
                    List(selection: $selectedHighlightIDs) {
                        ForEach(displayedRows) { row in
                            QuotesListRowView(row: row)
                                .equatable()
                                .tag(row.id)
                                .onAppear {
                                    loadMoreIfNeeded(currentHighlightID: row.id)
                                }
                        }

                        if isLoadingNextPage {
                            loadingMoreRow
                        }
                    }
                    .listStyle(.inset)
                } else {
                    List {
                        ForEach(displayedRows) { row in
                            NavigationLink(value: SettingsDestination.quoteDetail(row.id)) {
                                QuotesListRowView(row: row)
                                    .equatable()
                            }
                            .onAppear {
                                loadMoreIfNeeded(currentHighlightID: row.id)
                            }
                        }

                        if isLoadingNextPage {
                            loadingMoreRow
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(20)
        .background(
            QuotesListRenderCompletionObserver(
                token: renderObservationToken,
                displayedCount: displayedRows.count,
                onRendered: completeRenderMeasurement
            )
            .frame(width: 0, height: 0)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .searchable(text: $searchText, prompt: "Search quotes, books, or authors")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive, action: deleteSelectedHighlights) {
                    Label("Delete Selected", systemImage: "trash")
                }
                .disabled(QuotesBulkSelectionPresentationModel.bulkDeleteButtonDisabled(
                    isEditing: isEditingHighlights,
                    selectedHighlightIDs: selectedHighlightIDs
                ))
                .help(deleteSelectedHelpText)

                Button(isEditingHighlights ? "Done" : "Edit") {
                    toggleHighlightsEditMode()
                }

                Button {
                    isPresentingAddQuote = true
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add Quote")
                .disabled(isEditingHighlights)
            }
        }
        .sheet(isPresented: $isPresentingAddQuote) {
            NavigationStack {
                QuoteEditView(
                    highlight: nil,
                    books: appState.books,
                    onCancel: {
                        isPresentingAddQuote = false
                    },
                    onSave: { request in
                        appState.addManualQuote(request)
                        isPresentingAddQuote = false
                    }
                )
            }
            .frame(minWidth: 520, minHeight: 460)
        }
        .onAppear {
            refreshHighlights(reason: "appear")
        }
        .onChange(of: sortMode) { _ in
            refreshHighlights(reason: "sortChanged")
        }
        .onChange(of: searchText) { _ in
            refreshHighlights(reason: "searchChanged")
        }
        .onChange(of: filters.selectedBookTitle) { _ in
            refreshHighlights(reason: "bookFilterChanged")
        }
        .onChange(of: filters.selectedAuthor) { _ in
            refreshHighlights(reason: "authorFilterChanged")
        }
        .onChange(of: filters.bookStatus) { _ in
            refreshHighlights(reason: "bookStatusChanged")
        }
        .onChange(of: filters.source) { _ in
            refreshHighlights(reason: "sourceFilterChanged")
        }
        .onReceive(appState.$totalHighlightCount) { _ in
            refreshHighlights(reason: "libraryChanged")
        }
        .onDisappear(perform: cancelQuotesLoading)
        .alert(
            QuotesBulkSelectionPresentationModel.bulkDeleteConfirmationTitle(
                selectedCount: pendingBulkDeleteHighlightIDs.count
            ),
            isPresented: bulkDeleteConfirmationPresentedBinding
        ) {
            Button("Delete", role: .destructive) {
                confirmBulkDeleteHighlights()
            }
            Button("Cancel", role: .cancel) {
                pendingBulkDeleteHighlightIDs.removeAll()
            }
        } message: {
            Text(
                QuotesBulkSelectionPresentationModel.bulkDeleteConfirmationMessage(
                    selectedCount: pendingBulkDeleteHighlightIDs.count
                )
            )
        }
    }

    private func controlsRow(displayedCount: Int) -> some View {
        VStack(alignment: .leading, spacing: 12) {
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

                Text(resultCountSummary(displayedCount: displayedCount))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .center, spacing: 12) {
                    Picker("Book", selection: $filters.selectedBookTitle) {
                        Text("All Books")
                            .tag(nil as String?)

                        ForEach(availableBookTitles, id: \.self) { title in
                            Text(title)
                                .tag(title as String?)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Author", selection: $filters.selectedAuthor) {
                        Text("All Authors")
                            .tag(nil as String?)

                        ForEach(availableAuthors, id: \.self) { author in
                            Text(author)
                                .tag(author as String?)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Book Status", selection: $filters.bookStatus) {
                        ForEach(QuotesListBookStatusFilterMode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    Picker("Manual Added", selection: $filters.source) {
                        ForEach(QuotesListSourceFilterMode.allCases) { mode in
                            Text(mode.title)
                                .tag(mode)
                        }
                    }
                    .pickerStyle(.menu)

                    if filters.isActive {
                        Button("Reset Filters") {
                            filters = QuotesListFilters()
                        }
                    }
                }
            }
        }
    }

    private func resultCountSummary(displayedCount: Int) -> String {
        QuotesBulkSelectionPresentationModel.resultCountSummary(
            displayedCount: displayedCount,
            totalCount: totalMatchingHighlightCount,
            hasActiveQuery: hasActiveQuery,
            isEditing: isEditingHighlights,
            selectedCount: selectedHighlightIDs.count
        )
    }

    private var shouldShowImportHeader: Bool {
        isLoadingHighlights || appState.totalHighlightCount > 0 && !rowModels.isEmpty
    }

    private var hasActiveQuery: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || filters.isActive
    }

    private var deleteSelectedHelpText: String {
        if !isEditingHighlights {
            return "Enter Edit Mode to Delete Quotes"
        }

        if selectedHighlightIDs.isEmpty {
            return "Select Quotes to Delete"
        }

        return "Delete Selected Quotes"
    }

    private var bulkDeleteConfirmationPresentedBinding: Binding<Bool> {
        Binding(
            get: { !pendingBulkDeleteHighlightIDs.isEmpty },
            set: { isPresented in
                if !isPresented {
                    pendingBulkDeleteHighlightIDs.removeAll()
                }
            }
        )
    }

    private var loadingMoreRow: some View {
        HStack {
            Spacer()
            ProgressView()
            Spacer()
        }
        .padding(.vertical, 8)
        .listRowSeparator(.hidden)
        .allowsHitTesting(false)
    }

    private func refreshHighlights() {
        refreshHighlights(reason: "refresh")
    }

    private func refreshHighlights(reason: String) {
        cancelActiveQuotesTasks()
        cancelPendingMeasurements()

        let resetState = QuotesListPagingPresentationModel.refreshResetState(
            after: queryGeneration,
            preservingHighlights: highlights,
            totalMatchingHighlightCount: totalMatchingHighlightCount,
            availableBookTitles: availableBookTitles,
            availableAuthors: availableAuthors,
            selectedHighlightIDs: selectedHighlightIDs
        )
        let currentGeneration = resetState.nextQueryGeneration
        queryGeneration = currentGeneration
        isLoadingHighlights = resetState.isLoadingHighlights
        isLoadingNextPage = resetState.isLoadingNextPage
        hasMoreHighlights = resetState.hasMoreHighlights
        highlights = resetState.highlights
        rowModels = makeRowModels(from: resetState.highlights)
        totalMatchingHighlightCount = resetState.totalMatchingHighlightCount
        availableBookTitles = resetState.availableBookTitles
        availableAuthors = resetState.availableAuthors
        selectedHighlightIDs = resetState.selectedHighlightIDs

        pendingRefreshSignpostState = QuotesListPerformanceSignposts.beginRefresh(
            reason: reason,
            sortMode: sortMode
        )

        let currentSearchText = searchText
        let currentFilters = filters
        let currentSortMode = sortMode
        let quotesQueryService = appState.quotesQueryService
        refreshTask = Task {
            let snapshot = await quotesQueryService.loadSnapshot(
                searchText: currentSearchText,
                filters: currentFilters,
                sortedBy: currentSortMode,
                pageSize: QuotesListPagingConstants.pageSize
            )

            guard !Task.isCancelled, currentGeneration == queryGeneration else {
                return
            }

            availableBookTitles = snapshot.availableBookTitles
            availableAuthors = snapshot.availableAuthors

            guard reconcileFilters() == false else {
                refreshTask = nil
                return
            }

            highlights = snapshot.highlights
            rowModels = makeRowModels(from: snapshot.highlights)
            totalMatchingHighlightCount = snapshot.totalMatchingHighlightCount
            hasMoreHighlights = QuotesListPagingPresentationModel.hasMoreHighlights(
                loadedCount: snapshot.highlights.count,
                totalMatchingHighlightCount: snapshot.totalMatchingHighlightCount
            )
            isLoadingHighlights = false
            refreshTask = nil
            reconcileSelectedHighlights()
            completeRefreshMeasurement(loadedCount: snapshot.highlights.count)

            pendingRenderSignpostState = QuotesListPerformanceSignposts.beginRender(
                reason: reason,
                sortMode: currentSortMode,
                totalCount: snapshot.highlights.count
            )
            renderObservationToken = UUID()
        }
    }

    private func completeRenderMeasurement(token: UUID, displayedCount: Int) {
        guard token == renderObservationToken, let pendingRenderSignpostState else {
            return
        }

        QuotesListPerformanceSignposts.endRender(
            pendingRenderSignpostState,
            displayedCount: displayedCount
        )
        self.pendingRenderSignpostState = nil
    }

    private func cancelPendingMeasurements() {
        cancelPendingRefreshMeasurement()
        cancelPendingRenderMeasurement()
    }

    private func cancelPendingRefreshMeasurement() {
        guard let pendingRefreshSignpostState else {
            return
        }

        QuotesListPerformanceSignposts.cancelRefresh(pendingRefreshSignpostState)
        self.pendingRefreshSignpostState = nil
    }

    private func cancelPendingRenderMeasurement() {
        guard let pendingRenderSignpostState else {
            return
        }

        QuotesListPerformanceSignposts.cancelRender(pendingRenderSignpostState)
        self.pendingRenderSignpostState = nil
    }

    private func completeRefreshMeasurement(loadedCount: Int) {
        guard let pendingRefreshSignpostState else {
            return
        }

        QuotesListPerformanceSignposts.endRefresh(
            pendingRefreshSignpostState,
            loadedCount: loadedCount
        )
        self.pendingRefreshSignpostState = nil
    }

    private func reconcileFilters() -> Bool {
        var didChange = false

        if let selectedBookTitle = filters.selectedBookTitle,
           !availableBookTitles.contains(selectedBookTitle) {
            filters.selectedBookTitle = nil
            didChange = true
        }

        if let selectedAuthor = filters.selectedAuthor,
           !availableAuthors.contains(selectedAuthor) {
            filters.selectedAuthor = nil
            didChange = true
        }

        return didChange
    }

    private func reconcileSelectedHighlights() {
        selectedHighlightIDs = QuotesBulkSelectionPresentationModel.reconciledSelection(
            selectedHighlightIDs,
            validHighlightIDs: highlights.map(\.id)
        )
    }

    private func toggleHighlightsEditMode() {
        isEditingHighlights.toggle()

        if !isEditingHighlights {
            selectedHighlightIDs.removeAll()
        }
    }

    private func loadMoreIfNeeded(currentHighlightID: UUID) {
        guard QuotesListPagingPresentationModel.shouldLoadMore(
            highlights: highlights,
            currentHighlightID: currentHighlightID,
            hasMoreHighlights: hasMoreHighlights,
            isLoadingHighlights: isLoadingHighlights,
            isLoadingNextPage: isLoadingNextPage,
            hasLoadMoreTask: loadMoreTask != nil
        ) else {
            return
        }

        isLoadingNextPage = true
        let currentGeneration = queryGeneration
        let currentSearchText = searchText
        let currentFilters = filters
        let currentSortMode = sortMode
        let currentOffset = highlights.count
        let quotesQueryService = appState.quotesQueryService

        loadMoreTask = Task {
            let nextPage = await quotesQueryService.loadPage(
                searchText: currentSearchText,
                filters: currentFilters,
                sortedBy: currentSortMode,
                limit: QuotesListPagingConstants.pageSize,
                offset: currentOffset
            )

            guard !Task.isCancelled, currentGeneration == queryGeneration else {
                return
            }

            let appendResult = QuotesListPagingPresentationModel.appendPage(
                existingHighlights: highlights,
                nextPage: nextPage,
                totalMatchingHighlightCount: totalMatchingHighlightCount
            )
            highlights = appendResult.highlights
            rowModels = makeRowModels(from: appendResult.highlights)
            hasMoreHighlights = appendResult.hasMoreHighlights
            isLoadingNextPage = false
            loadMoreTask = nil
            reconcileSelectedHighlights()
        }
    }

    private func cancelActiveQuotesTasks() {
        refreshTask?.cancel()
        refreshTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        isLoadingHighlights = false
        isLoadingNextPage = false
    }

    private func cancelQuotesLoading() {
        cancelActiveQuotesTasks()
        cancelPendingMeasurements()
    }

    private func deleteSelectedHighlights() {
        let highlightIDsToDelete = QuotesBulkSelectionPresentationModel.bulkDeleteHighlightIDs(
            from: highlights,
            selectedHighlightIDs: selectedHighlightIDs
        )
        guard !highlightIDsToDelete.isEmpty else {
            return
        }

        pendingBulkDeleteHighlightIDs = highlightIDsToDelete
    }

    private func confirmBulkDeleteHighlights() {
        guard !pendingBulkDeleteHighlightIDs.isEmpty else {
            return
        }

        let highlightIDsToDelete = pendingBulkDeleteHighlightIDs
        appState.deleteHighlights(ids: highlightIDsToDelete)
        pendingBulkDeleteHighlightIDs.removeAll()
        selectedHighlightIDs.removeAll()
    }

    private func makeRowModels(from highlights: [Highlight]) -> [QuotesListRowModel] {
        highlights.map(QuotesListRowModel.init)
    }
}

private enum QuotesBulkSelectionPresentationModel {
    static func reconciledSelection(
        _ selectedHighlightIDs: Set<UUID>,
        validHighlightIDs: [UUID]
    ) -> Set<UUID> {
        let validHighlightIDSet = Set(validHighlightIDs)
        return selectedHighlightIDs.intersection(validHighlightIDSet)
    }

    static func bulkDeleteHighlightIDs(
        from highlights: [Highlight],
        selectedHighlightIDs: Set<UUID>
    ) -> [UUID] {
        highlights.map(\.id).filter(selectedHighlightIDs.contains)
    }

    static func bulkDeleteButtonDisabled(
        isEditing: Bool,
        selectedHighlightIDs: Set<UUID>
    ) -> Bool {
        !isEditing || selectedHighlightIDs.isEmpty
    }

    static func bulkDeleteConfirmationTitle(selectedCount: Int) -> String {
        "Delete \(selectedCount) \(selectedCount == 1 ? "Quote" : "Quotes")?"
    }

    static func bulkDeleteConfirmationMessage(selectedCount: Int) -> String {
        "This will permanently remove \(selectedCount) selected \(selectedCount == 1 ? "quote" : "quotes") from your library."
    }

    static func resultCountSummary(
        displayedCount: Int,
        totalCount: Int,
        hasActiveQuery: Bool,
        isEditing: Bool,
        selectedCount: Int
    ) -> String {
        let displayedSummary = displayedSummaryText(
            displayedCount: displayedCount,
            totalCount: totalCount,
            hasActiveQuery: hasActiveQuery
        )

        guard isEditing else {
            return displayedSummary
        }

        return "\(displayedSummary) • \(selectedCount) selected"
    }

    private static func displayedSummaryText(
        displayedCount: Int,
        totalCount: Int,
        hasActiveQuery: Bool
    ) -> String {
        if totalCount == 0 {
            return "0 quotes"
        }

        let noun = displayedCount == 1 ? "quote" : "quotes"

        if !hasActiveQuery {
            return "\(displayedCount) \(noun)"
        }

        return "\(displayedCount) of \(totalCount) \(totalCount == 1 ? "quote" : "quotes")"
    }
}

private struct QuotesEmptyStateView: View {
    let title: String
    let systemImage: String
    let description: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(.init(description))
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct QuoteDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState

    @State private var highlight: Highlight
    @State private var isShowingDeleteConfirmation = false
    @State private var isPresentingEditQuote = false
    @State private var wallpaperRequestMessage: String?
    @State private var toggleMessage: String?

    init(highlight: Highlight) {
        _highlight = State(initialValue: highlight)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 12) {
                    Text(highlight.quoteText)
                        .font(.title3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(QuotesListPresentationModel.bookTitleText(for: highlight))
                            .font(.headline)
                        Text("•")
                            .foregroundStyle(.tertiary)
                        Text(QuotesListPresentationModel.authorText(for: highlight))
                            .foregroundStyle(.secondary)
                    }
                }

                HStack(spacing: 12) {
                    Button("Edit") {
                        isPresentingEditQuote = true
                    }
                    .buttonStyle(.bordered)

                    Button("Set as Current Wallpaper") {
                        let didRequestRotation = appState.requestWallpaperRotation(forcedHighlight: highlight)
                        wallpaperRequestMessage = didRequestRotation
                            ? "Wallpaper update requested."
                            : "Wallpaper update already in progress."
                    }
                    .buttonStyle(.borderedProminent)

                    Button(Self.toggleButtonTitle(isEnabled: highlight.isEnabled)) {
                        toggleHighlightEnabled()
                    }
                    .buttonStyle(.bordered)
                }

                Button("Delete Quote", role: .destructive) {
                    isShowingDeleteConfirmation = true
                }

                if let wallpaperRequestMessage {
                    Text(wallpaperRequestMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                if let toggleMessage {
                    Text(toggleMessage)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 12) {
                    detailRow(label: "Location", value: detailLocationText)
                    detailRow(label: "Date Added", value: formattedDate(highlight.dateAdded))
                    detailRow(label: "Last Shown", value: formattedDate(highlight.lastShownAt))
                    detailRow(
                        label: "Included in Rotation",
                        value: Self.effectiveRotationStatusText(
                            quoteIsEnabled: highlight.isEnabled,
                            bookIsEnabled: linkedBookIsEnabled
                        )
                    )
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Quote")
        .sheet(isPresented: $isPresentingEditQuote) {
            NavigationStack {
                QuoteEditView(
                    highlight: highlight,
                    books: appState.books,
                    onCancel: {
                        isPresentingEditQuote = false
                    },
                    onSave: { request in
                        let updatedHighlight = try appState.updateQuote(highlight, with: request)
                        highlight = updatedHighlight
                        wallpaperRequestMessage = nil
                        toggleMessage = nil
                        isPresentingEditQuote = false
                    }
                )
            }
            .frame(minWidth: 520, minHeight: 460)
        }
        .alert("Delete Quote?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                appState.deleteHighlight(id: highlight.id)
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This quote will be removed from your library.")
        }
    }

    private var detailLocationText: String {
        let trimmedLocation = highlight.location?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmedLocation.isEmpty ? "Not available" : trimmedLocation
    }

    private var linkedBookIsEnabled: Bool? {
        guard let bookID = highlight.bookId else {
            return nil
        }

        return appState.books.first(where: { $0.id == bookID })?.isEnabled
    }

    private func detailRow(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
        }
    }

    private func formattedDate(_ date: Date?) -> String {
        guard let date else {
            return "Not available"
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }

    private func toggleHighlightEnabled() {
        let enabled = !highlight.isEnabled
        appState.setHighlightEnabled(id: highlight.id, enabled: enabled)

        let updatedHighlight = Self.updatedHighlight(highlight, isEnabled: enabled)
        highlight = updatedHighlight
        toggleMessage = Self.toggleStatusMessage(
            isEnabled: enabled,
            bookIsEnabled: linkedBookIsEnabled
        )
    }

    static func toggleButtonTitle(isEnabled: Bool) -> String {
        isEnabled ? "Disable from Rotation" : "Enable for Rotation"
    }

    static func effectiveRotationStatusText(quoteIsEnabled: Bool, bookIsEnabled: Bool?) -> String {
        guard quoteIsEnabled else {
            return "No"
        }

        if bookIsEnabled == false {
            return "No (book disabled)"
        }

        return "Yes"
    }

    static func toggleStatusMessage(isEnabled: Bool, bookIsEnabled: Bool?) -> String {
        if isEnabled {
            return bookIsEnabled == false
                ? "Quote enabled. It will rotate once its book is enabled."
                : "Quote enabled for rotation."
        }

        return "Quote removed from rotation."
    }

    static func updatedHighlight(_ highlight: Highlight, isEnabled: Bool) -> Highlight {
        Highlight(
            id: highlight.id,
            bookId: highlight.bookId,
            quoteText: highlight.quoteText,
            bookTitle: highlight.bookTitle,
            author: highlight.author,
            location: highlight.location,
            dateAdded: highlight.dateAdded,
            lastShownAt: isEnabled ? nil : highlight.lastShownAt,
            isEnabled: isEnabled
        )
    }
}

struct QuoteEditView: View {
    let highlight: Highlight?
    let books: [Book]
    let onCancel: () -> Void
    let onSave: (QuoteEditSaveRequest) throws -> Void

    @State private var draft: QuoteEditDraft
    @State private var saveError: AppState.QuoteSaveError?

    init(
        highlight: Highlight?,
        books: [Book],
        onCancel: @escaping () -> Void,
        onSave: @escaping (QuoteEditSaveRequest) throws -> Void
    ) {
        self.highlight = highlight
        self.books = books
        self.onCancel = onCancel
        self.onSave = onSave
        _draft = State(initialValue: QuoteEditDraft(highlight: highlight))
    }

    var body: some View {
        Form {
            if let saveError {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Unable to Save Quote", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)

                        Text(QuoteEditPresentationModel.errorMessage(for: saveError))
                            .fixedSize(horizontal: false, vertical: true)

                        if let recoverySuggestion = QuoteEditPresentationModel.errorRecoverySuggestion(for: saveError) {
                            Text(recoverySuggestion)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button("Dismiss") {
                            self.saveError = nil
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section("Quote") {
                TextEditor(text: $draft.quoteText)
                    .frame(minHeight: 180)
            }

            Section("Details") {
                TextField("Book Title", text: $draft.bookTitle)
                TextField("Author", text: $draft.author)
                TextField("Location", text: $draft.location)

                LabeledContent("Linked Book") {
                    if let matchedBook {
                        Text("\(matchedBook.title) by \(matchedBook.author)")
                    } else {
                        Text("None")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onCancel()
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveError = nil

                    do {
                        try onSave(QuoteEditPresentationModel.saveRequest(draft: draft, books: books))
                    } catch let error as AppState.QuoteSaveError {
                        saveError = error
                    } catch {
                        assertionFailure("Unexpected quote save error: \(error)")
                    }
                }
                .disabled(!canSave)
            }
        }
    }

    private var title: String {
        QuoteEditPresentationModel.title(for: highlight)
    }

    private var matchedBook: Book? {
        QuoteEditPresentationModel.matchedBook(
            bookTitle: draft.bookTitle,
            author: draft.author,
            books: books
        )
    }

    private var canSave: Bool {
        QuoteEditPresentationModel.canSave(quoteText: draft.quoteText)
    }
}

#if TESTING
enum QuoteDetailViewTestProbe {
    static func toggleButtonTitle(isEnabled: Bool) -> String {
        QuoteDetailView.toggleButtonTitle(isEnabled: isEnabled)
    }

    static func effectiveRotationStatusText(quoteIsEnabled: Bool, bookIsEnabled: Bool?) -> String {
        QuoteDetailView.effectiveRotationStatusText(quoteIsEnabled: quoteIsEnabled, bookIsEnabled: bookIsEnabled)
    }

    static func toggleStatusMessage(isEnabled: Bool, bookIsEnabled: Bool?) -> String {
        QuoteDetailView.toggleStatusMessage(isEnabled: isEnabled, bookIsEnabled: bookIsEnabled)
    }

    static func updatedHighlight(_ highlight: Highlight, isEnabled: Bool) -> Highlight {
        QuoteDetailView.updatedHighlight(highlight, isEnabled: isEnabled)
    }
}

enum QuotesListViewTestProbe {
    static func refreshResetState(after currentQueryGeneration: Int) -> (
        nextQueryGeneration: Int,
        isLoadingHighlights: Bool,
        isLoadingNextPage: Bool,
        hasMoreHighlights: Bool,
        highlightCount: Int,
        totalMatchingHighlightCount: Int,
        availableBookTitles: [String],
        availableAuthors: [String]
    ) {
        let state = QuotesListPagingPresentationModel.refreshResetState(after: currentQueryGeneration)
        return (
            nextQueryGeneration: state.nextQueryGeneration,
            isLoadingHighlights: state.isLoadingHighlights,
            isLoadingNextPage: state.isLoadingNextPage,
            hasMoreHighlights: state.hasMoreHighlights,
            highlightCount: state.highlights.count,
            totalMatchingHighlightCount: state.totalMatchingHighlightCount,
            availableBookTitles: state.availableBookTitles,
            availableAuthors: state.availableAuthors
        )
    }

    static func refreshResetState(
        after currentQueryGeneration: Int,
        preservingHighlights: [Highlight],
        totalMatchingHighlightCount: Int,
        availableBookTitles: [String],
        availableAuthors: [String],
        selectedHighlightIDs: Set<UUID>
    ) -> (
        nextQueryGeneration: Int,
        isLoadingHighlights: Bool,
        isLoadingNextPage: Bool,
        hasMoreHighlights: Bool,
        highlightIDs: [UUID],
        totalMatchingHighlightCount: Int,
        availableBookTitles: [String],
        availableAuthors: [String],
        selectedHighlightIDs: Set<UUID>
    ) {
        let state = QuotesListPagingPresentationModel.refreshResetState(
            after: currentQueryGeneration,
            preservingHighlights: preservingHighlights,
            totalMatchingHighlightCount: totalMatchingHighlightCount,
            availableBookTitles: availableBookTitles,
            availableAuthors: availableAuthors,
            selectedHighlightIDs: selectedHighlightIDs
        )
        return (
            nextQueryGeneration: state.nextQueryGeneration,
            isLoadingHighlights: state.isLoadingHighlights,
            isLoadingNextPage: state.isLoadingNextPage,
            hasMoreHighlights: state.hasMoreHighlights,
            highlightIDs: state.highlights.map(\.id),
            totalMatchingHighlightCount: state.totalMatchingHighlightCount,
            availableBookTitles: state.availableBookTitles,
            availableAuthors: state.availableAuthors,
            selectedHighlightIDs: state.selectedHighlightIDs
        )
    }

    static func hasMoreHighlights(
        loadedCount: Int,
        totalMatchingHighlightCount: Int
    ) -> Bool {
        QuotesListPagingPresentationModel.hasMoreHighlights(
            loadedCount: loadedCount,
            totalMatchingHighlightCount: totalMatchingHighlightCount
        )
    }

    static func shouldLoadMore(
        highlights: [Highlight],
        currentHighlightID: UUID,
        hasMoreHighlights: Bool,
        isLoadingHighlights: Bool,
        isLoadingNextPage: Bool,
        hasLoadMoreTask: Bool
    ) -> Bool {
        QuotesListPagingPresentationModel.shouldLoadMore(
            highlights: highlights,
            currentHighlightID: currentHighlightID,
            hasMoreHighlights: hasMoreHighlights,
            isLoadingHighlights: isLoadingHighlights,
            isLoadingNextPage: isLoadingNextPage,
            hasLoadMoreTask: hasLoadMoreTask
        )
    }

    static func appendPage(
        existingHighlights: [Highlight],
        nextPage: [Highlight],
        totalMatchingHighlightCount: Int
    ) -> (highlightIDs: [UUID], hasMoreHighlights: Bool) {
        let result = QuotesListPagingPresentationModel.appendPage(
            existingHighlights: existingHighlights,
            nextPage: nextPage,
            totalMatchingHighlightCount: totalMatchingHighlightCount
        )
        return (
            highlightIDs: result.highlights.map(\.id),
            hasMoreHighlights: result.hasMoreHighlights
        )
    }

    static func displayedHighlightIDs(
        from highlights: [Highlight],
        searchText: String,
        sortMode: QuotesListSortMode,
        books: [Book] = [],
        selectedBookTitle: String? = nil,
        selectedAuthor: String? = nil,
        bookStatus: QuotesListBookStatusFilterMode = .allBooks,
        source: QuotesListSourceFilterMode = .allQuotes
    ) -> [UUID] {
        let sortedHighlights = QuotesListPresentationModel.sortedHighlights(
            highlights,
            sortMode: sortMode
        )

        return QuotesListPresentationModel.displayedHighlights(
            from: sortedHighlights,
            searchText: searchText,
            filters: QuotesListFilters(
                selectedBookTitle: selectedBookTitle,
                selectedAuthor: selectedAuthor,
                bookStatus: bookStatus,
                source: source
            ),
            bookEnabledByID: Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0.isEnabled) })
        ).map(\.id)
    }

    static func filteredHighlightIDs(
        from highlights: [Highlight],
        searchText: String,
        books: [Book] = [],
        selectedBookTitle: String? = nil,
        selectedAuthor: String? = nil,
        bookStatus: QuotesListBookStatusFilterMode = .allBooks,
        source: QuotesListSourceFilterMode = .allQuotes
    ) -> [UUID] {
        QuotesListPresentationModel.displayedHighlights(
            from: highlights,
            searchText: searchText,
            filters: QuotesListFilters(
                selectedBookTitle: selectedBookTitle,
                selectedAuthor: selectedAuthor,
                bookStatus: bookStatus,
                source: source
            ),
            bookEnabledByID: Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0.isEnabled) })
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

    static func availableBookTitles(from highlights: [Highlight]) -> [String] {
        QuotesListPresentationModel.availableBookTitles(from: highlights)
    }

    static func availableAuthors(from highlights: [Highlight]) -> [String] {
        QuotesListPresentationModel.availableAuthors(from: highlights)
    }

    static func reconciledSelection(
        _ selectedHighlightIDs: Set<UUID>,
        validHighlightIDs: [UUID]
    ) -> Set<UUID> {
        QuotesBulkSelectionPresentationModel.reconciledSelection(
            selectedHighlightIDs,
            validHighlightIDs: validHighlightIDs
        )
    }

    static func bulkDeleteHighlightIDs(
        from highlights: [Highlight],
        selectedHighlightIDs: Set<UUID>
    ) -> [UUID] {
        QuotesBulkSelectionPresentationModel.bulkDeleteHighlightIDs(
            from: highlights,
            selectedHighlightIDs: selectedHighlightIDs
        )
    }

    static func bulkDeleteButtonDisabled(
        isEditing: Bool,
        selectedHighlightIDs: Set<UUID>
    ) -> Bool {
        QuotesBulkSelectionPresentationModel.bulkDeleteButtonDisabled(
            isEditing: isEditing,
            selectedHighlightIDs: selectedHighlightIDs
        )
    }

    static func bulkDeleteConfirmationTitle(selectedCount: Int) -> String {
        QuotesBulkSelectionPresentationModel.bulkDeleteConfirmationTitle(selectedCount: selectedCount)
    }

    static func bulkDeleteConfirmationMessage(selectedCount: Int) -> String {
        QuotesBulkSelectionPresentationModel.bulkDeleteConfirmationMessage(selectedCount: selectedCount)
    }

    static func resultCountSummary(
        displayedCount: Int,
        totalCount: Int,
        hasActiveQuery: Bool,
        isEditing: Bool,
        selectedCount: Int
    ) -> String {
        QuotesBulkSelectionPresentationModel.resultCountSummary(
            displayedCount: displayedCount,
            totalCount: totalCount,
            hasActiveQuery: hasActiveQuery,
            isEditing: isEditing,
            selectedCount: selectedCount
        )
    }
}

enum BooksListViewTestProbe {
    static func reconciledSelection(
        _ selectedBookIDs: Set<UUID>,
        validBookIDs: [UUID]
    ) -> Set<UUID> {
        BooksBulkSelectionPresentationModel.reconciledSelection(
            selectedBookIDs,
            validBookIDs: validBookIDs
        )
    }

    static func bulkDeleteBookIDs(
        from books: [Book],
        selectedBookIDs: Set<UUID>
    ) -> [UUID] {
        BooksBulkSelectionPresentationModel.bulkDeleteBookIDs(
            from: books,
            selectedBookIDs: selectedBookIDs
        )
    }

    static func bulkDeleteButtonDisabled(
        isEditing: Bool,
        selectedBookIDs: Set<UUID>
    ) -> Bool {
        BooksBulkSelectionPresentationModel.bulkDeleteButtonDisabled(
            isEditing: isEditing,
            selectedBookIDs: selectedBookIDs
        )
    }

    static func bulkDeleteConfirmationTitle(plan: BulkBookDeletionPlan) -> String {
        BooksBulkSelectionPresentationModel.bulkDeleteConfirmationTitle(plan: plan)
    }

    static func bulkDeleteConfirmationMessage(plan: BulkBookDeletionPlan) -> String {
        BooksBulkSelectionPresentationModel.bulkDeleteConfirmationMessage(plan: plan)
    }
}

enum QuoteEditViewTestProbe {
    struct DraftSnapshot {
        let quoteText: String
        let bookTitle: String
        let author: String
        let location: String
    }

    static func title(for highlight: Highlight?) -> String {
        QuoteEditPresentationModel.title(for: highlight)
    }

    static func draftSnapshot(from highlight: Highlight?) -> DraftSnapshot {
        let draft = QuoteEditDraft(highlight: highlight)
        return DraftSnapshot(
            quoteText: draft.quoteText,
            bookTitle: draft.bookTitle,
            author: draft.author,
            location: draft.location
        )
    }

    static func canSave(quoteText: String) -> Bool {
        QuoteEditPresentationModel.canSave(quoteText: quoteText)
    }

    static func errorMessage(for error: AppState.QuoteSaveError) -> String {
        QuoteEditPresentationModel.errorMessage(for: error)
    }

    static func errorRecoverySuggestion(for error: AppState.QuoteSaveError) -> String? {
        QuoteEditPresentationModel.errorRecoverySuggestion(for: error)
    }

    static func matchedBookID(
        bookTitle: String,
        author: String,
        books: [Book]
    ) -> UUID? {
        QuoteEditPresentationModel.matchedBook(
            bookTitle: bookTitle,
            author: author,
            books: books
        )?.id
    }

    static func saveRequest(
        quoteText: String,
        bookTitle: String,
        author: String,
        location: String,
        books: [Book]
    ) -> QuoteEditSaveRequest {
        QuoteEditPresentationModel.saveRequest(
            draft: QuoteEditDraft(
                quoteText: quoteText,
                bookTitle: bookTitle,
                author: author,
                location: location
            ),
            books: books
        )
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

            if !appState.importWarningDetails.isEmpty {
                warningDetailsView(appState.importWarningDetails)
            }
        }
    }

    private func settingsMessageRow(_ message: String, tone: SettingsMessageTone = .primary) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(tone.color)
    }

    private func warningDetailsView(_ details: [String]) -> some View {
        DisclosureGroup("Warning details") {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(details.enumerated()), id: \.offset) { _, detail in
                    Text(detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 4)
        }
        .font(.callout)
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
            skippedEntryCount: result.skippedEntryCount,
            warningMessages: result.warningMessages
        ),
        now: Date()
    )
    appState.setImportStatus(
        AppState.ImportStatus(
            message: status.message,
            isError: status.isError,
            warningDetails: status.warningDetails
        )
    )
    if let librarySnapshot = result.librarySnapshot {
        appState.applyLibrarySnapshot(librarySnapshot)
    } else {
        appState.refreshLibraryState()
    }
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
    @State private var selectedBookIDs: Set<UUID> = []
    @State private var pendingBulkBookDeletionPlan: BulkBookDeletionPlan? = nil
    @State private var isEditingBooks = false

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

                Spacer(minLength: 12)
            }

            Group {
                if isEditingBooks {
                    List(selection: $selectedBookIDs) {
                        if appState.books.isEmpty {
                            Text("No books imported yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(appState.books) { book in
                                bookSelectionRow(book)
                                    .tag(book.id)
                            }
                        }
                    }
                    .listStyle(.inset)
                } else {
                    List {
                        if appState.books.isEmpty {
                            Text("No books imported yet.")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(appState.books) { book in
                                bookToggleRow(book)
                            }
                        }
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if allBooksDeselectedWarningVisible {
                Text("All books are deselected. Wallpaper rotation has no active quote pool.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive, action: deleteSelectedBooks) {
                    Label("Delete Selected", systemImage: "trash")
                }
                .disabled(BooksBulkSelectionPresentationModel.bulkDeleteButtonDisabled(
                    isEditing: isEditingBooks,
                    selectedBookIDs: selectedBookIDs
                ))
                .help(deleteSelectedHelpText)

                Button(isEditingBooks ? "Done" : "Edit") {
                    toggleBooksEditMode()
                }
            }
        }
        .onReceive(appState.$books) { _ in
            reconcileSelectedBooks()
        }
        .alert(
            BooksBulkSelectionPresentationModel.bulkDeleteConfirmationTitle(
                plan: pendingBulkBookDeletionPlanValue
            ),
            isPresented: bulkDeleteConfirmationPresentedBinding
        ) {
            Button("Delete", role: .destructive) {
                confirmBulkDeleteBooks()
            }
            Button("Cancel", role: .cancel) {
                pendingBulkBookDeletionPlan = nil
            }
        } message: {
            Text(
                BooksBulkSelectionPresentationModel.bulkDeleteConfirmationMessage(
                    plan: pendingBulkBookDeletionPlanValue
                )
            )
        }
    }

    private var allBooksDeselectedWarningVisible: Bool {
        !appState.books.isEmpty && appState.books.allSatisfy { !$0.isEnabled }
    }

    private var deleteSelectedHelpText: String {
        if !isEditingBooks {
            return "Enter Edit Mode to Delete Books"
        }

        if selectedBookIDs.isEmpty {
            return "Select Books to Delete"
        }

        return "Delete Selected Books"
    }

    private var pendingBulkBookDeletionPlanValue: BulkBookDeletionPlan {
        pendingBulkBookDeletionPlan ?? BulkBookDeletionPlan(bookIDs: [], linkedHighlights: [])
    }

    private var bulkDeleteConfirmationPresentedBinding: Binding<Bool> {
        Binding(
            get: { pendingBulkBookDeletionPlan != nil },
            set: { isPresented in
                if !isPresented {
                    pendingBulkBookDeletionPlan = nil
                }
            }
        )
    }

    private func bookToggleRow(_ book: Book) -> some View {
        Toggle(isOn: bindingForBook(book)) {
            bookRowContent(book)
        }
        .toggleStyle(.checkbox)
        .disabled(appState.isBookMutationInFlight)
    }

    private func bookSelectionRow(_ book: Book) -> some View {
        bookRowContent(book)
            .padding(.vertical, 4)
    }

    private func bookRowContent(_ book: Book) -> some View {
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func reconcileSelectedBooks() {
        selectedBookIDs = BooksBulkSelectionPresentationModel.reconciledSelection(
            selectedBookIDs,
            validBookIDs: appState.books.map(\.id)
        )
    }

    private func toggleBooksEditMode() {
        isEditingBooks.toggle()

        if !isEditingBooks {
            selectedBookIDs.removeAll()
        }
    }

    private func deleteSelectedBooks() {
        let bookIDsToDelete = BooksBulkSelectionPresentationModel.bulkDeleteBookIDs(
            from: appState.books,
            selectedBookIDs: selectedBookIDs
        )
        guard !bookIDsToDelete.isEmpty else {
            return
        }

        let plan = appState.prepareBulkBookDeletion(bookIDs: bookIDsToDelete)
        pendingBulkBookDeletionPlan = plan
    }

    private func confirmBulkDeleteBooks() {
        guard let plan = pendingBulkBookDeletionPlan else {
            return
        }

        appState.deleteBooks(using: plan)
        pendingBulkBookDeletionPlan = nil
        selectedBookIDs.removeAll()
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

private enum BooksBulkSelectionPresentationModel {
    static func reconciledSelection(
        _ selectedBookIDs: Set<UUID>,
        validBookIDs: [UUID]
    ) -> Set<UUID> {
        let validBookIDSet = Set(validBookIDs)
        return selectedBookIDs.intersection(validBookIDSet)
    }

    static func bulkDeleteBookIDs(
        from books: [Book],
        selectedBookIDs: Set<UUID>
    ) -> [UUID] {
        books.map(\.id).filter(selectedBookIDs.contains)
    }

    static func bulkDeleteButtonDisabled(
        isEditing: Bool,
        selectedBookIDs: Set<UUID>
    ) -> Bool {
        !isEditing || selectedBookIDs.isEmpty
    }

    static func bulkDeleteConfirmationTitle(plan: BulkBookDeletionPlan) -> String {
        "Delete \(plan.bookCount) \(plan.bookCount == 1 ? "Book" : "Books")?"
    }

    static func bulkDeleteConfirmationMessage(plan: BulkBookDeletionPlan) -> String {
        let bookText = "\(plan.bookCount) selected \(plan.bookCount == 1 ? "book" : "books")"
        let quoteText = "\(plan.linkedHighlightCount) linked \(plan.linkedHighlightCount == 1 ? "quote" : "quotes")"
        return "This will permanently remove \(bookText) and delete \(quoteText) from your library."
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
