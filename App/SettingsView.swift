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
        Form {
            scheduleSection
            displaySection
            aboutSection
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
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
                subtitle: "\(backgroundCollectionCount) \(backgroundCollectionCount == 1 ? "image" : "images")",
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
            Toggle("Launch at Login", isOn: launchAtLoginBinding)
            settingsMessageRow(
                "Managed by macOS Login Items.",
                tone: .secondary
            )
            settingsMessageRow(launchAtLoginStatusMessage, tone: .secondary)
            if let error = appState.launchAtLoginErrorMessage {
                settingsMessageRow(error, tone: .error)
            }

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

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: {
                appState.isLaunchAtLoginEnabled
            },
            set: { enabled in
                appState.setLaunchAtLoginEnabled(enabled)
            }
        )
    }

    private var launchAtLoginStatusMessage: String {
        if appState.isLaunchAtLoginEnabled {
            return "KindleWall will open automatically when you log in."
        }
        return "KindleWall will not open automatically when you log in."
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

enum SettingsMessageTone {
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
