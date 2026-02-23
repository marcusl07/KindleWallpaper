import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var backgroundImageURL: URL? = nil
    @State private var backgroundImageError: String? = nil
    private let booksListHeight: CGFloat = 220

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 20) {
                importSection
                booksSection
                backgroundSection
                scheduleSection
                aboutSection
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshBackgroundThumbnail)
    }

    private var importSection: some View {
        sectionContainer(title: "Import") {
            Button("Import My Clippings.txt...") {
                chooseClippingsFile()
            }

            if let importError = appState.importError, !importError.isEmpty {
                Text(importError)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if !appState.importStatus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(appState.importStatus)
                    .font(.callout)
            } else {
                Text("No imports yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("\(appState.totalHighlightCount) \(appState.totalHighlightCount == 1 ? "highlight" : "highlights") in library")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var booksSection: some View {
        sectionContainer(title: "Books") {
            HStack(spacing: 12) {
                Button("Select All") {
                    appState.setAllBooksEnabled(true)
                }
                .disabled(appState.books.isEmpty || appState.books.allSatisfy(\.isEnabled))

                Button("Deselect All") {
                    appState.setAllBooksEnabled(false)
                }
                .disabled(appState.books.isEmpty || appState.books.allSatisfy { !$0.isEnabled })
            }

            List {
                if appState.books.isEmpty {
                    Text("No books imported yet.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    ForEach(appState.books) { book in
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
                    }
                }
            }
            .listStyle(.inset)
            .frame(minHeight: booksListHeight, idealHeight: booksListHeight, maxHeight: booksListHeight)

            if allBooksDeselectedWarningVisible {
                Text("All books are deselected. Wallpaper rotation has no active quote pool.")
                    .font(.callout)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var backgroundSection: some View {
        sectionContainer(title: "Background Image") {
            backgroundPreview

            if let backgroundImageError {
                Text(backgroundImageError)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            Button("Change Image...") {
                chooseBackgroundImage()
            }
        }
    }

    private var scheduleSection: some View {
        sectionContainer(title: "Rotation Schedule") {
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

            Text("Last changed: \(formattedLastChangedAt)")
                .font(.callout)

            Text("Timed rotation requires the app to be running.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSection: some View {
        sectionContainer(title: "About") {
            Text("KindleWall")
                .font(.headline)
            Text("Version \(appVersionDisplay)")
                .foregroundStyle(.secondary)
        }
    }

    private func sectionContainer<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GroupBox(label: Text(title).font(.headline)) {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private var backgroundPreview: some View {
        #if canImport(AppKit)
        if let image = loadPreviewImage() {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.black.opacity(0.12), lineWidth: 1)
                )
        } else {
            placeholderBackgroundPreview
        }
        #else
        placeholderBackgroundPreview
        #endif
    }

    private var placeholderBackgroundPreview: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.black)
            .frame(height: 160)
            .frame(maxWidth: .infinity)
            .overlay(
                Text("No image — black background")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            )
    }

    #if canImport(AppKit)
    private func loadPreviewImage() -> NSImage? {
        BackgroundImageLoader.shared.load(from: backgroundImageURL).image
    }
    #endif

    private func refreshBackgroundThumbnail() {
        let store = BackgroundImageStore()
        backgroundImageURL = store.loadBackgroundImageURL()
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

    private func chooseBackgroundImage() {
        #if canImport(AppKit)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.jpeg, .png, .heic]
        panel.title = "Choose Background Image"
        panel.prompt = "Choose Image"

        guard panel.runModal() == .OK, let selectedURL = panel.url else {
            return
        }

        do {
            let store = BackgroundImageStore()
            _ = try store.saveBackgroundImage(from: selectedURL)
            backgroundImageError = nil
            refreshBackgroundThumbnail()
        } catch {
            backgroundImageError = "Failed to set background image: \(error.localizedDescription)"
        }
        #endif
    }

    private func chooseClippingsFile() {
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

        importClippingsFile(at: selectedURL)
        #endif
    }

    private func importClippingsFile(at fileURL: URL) {
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

    private var allBooksDeselectedWarningVisible: Bool {
        !appState.books.isEmpty && appState.books.allSatisfy { !$0.isEnabled }
    }

    private func bindingForBook(_ book: Book) -> Binding<Bool> {
        Binding(
            get: {
                book.isEnabled
            },
            set: { enabled in
                guard book.isEnabled != enabled else {
                    return
                }
                appState.setBookEnabled(id: book.id, enabled: enabled)
            }
        )
    }
}
