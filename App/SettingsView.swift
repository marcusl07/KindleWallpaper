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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                importSectionPlaceholder
                booksSectionPlaceholder
                backgroundSection
                scheduleSectionPlaceholder
                aboutSectionPlaceholder
            }
            .padding(20)
        }
        .frame(minWidth: 680, minHeight: 520)
        .onAppear(perform: refreshBackgroundThumbnail)
    }

    private var importSectionPlaceholder: some View {
        sectionContainer(title: "Import") {
            Text("Import section coming next.")
                .foregroundStyle(.secondary)
        }
    }

    private var booksSectionPlaceholder: some View {
        sectionContainer(title: "Books") {
            Text("Books section coming next.")
                .foregroundStyle(.secondary)
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
}
