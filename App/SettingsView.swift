import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var backgroundImageURL: URL? = nil
    @State private var backgroundImageError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            importSectionPlaceholder
            booksSection
            backgroundSection
            scheduleSectionPlaceholder
            aboutSectionPlaceholder
        }
        .padding(20)
        .frame(minWidth: 680, maxWidth: .infinity, minHeight: 520, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: refreshBackgroundThumbnail)
    }

    private var importSectionPlaceholder: some View {
        sectionContainer(title: "Import") {
            Text("Import section coming next.")
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
            .frame(height: 220)

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

    private var scheduleSectionPlaceholder: some View {
        sectionContainer(title: "Rotation Schedule") {
            Text("Rotation schedule section coming next.")
                .foregroundStyle(.secondary)
        }
    }

    private var aboutSectionPlaceholder: some View {
        sectionContainer(title: "About") {
            Text("About section coming next.")
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
        guard let backgroundImageURL else {
            return nil
        }

        return NSImage(contentsOf: backgroundImageURL)
    }
    #endif

    private func refreshBackgroundThumbnail() {
        let store = BackgroundImageStore()
        backgroundImageURL = store.loadBackgroundImageURL()
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
