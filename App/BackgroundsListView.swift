import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct BackgroundsListView: View {
    @EnvironmentObject private var appState: AppState
    @State private var collectionState = AppState.BackgroundCollectionState(items: [], selectedItemID: nil, warningMessage: nil)
    @State private var selectedBackgroundID: UUID? = nil
    @State private var operationError: String? = nil
    @State private var isShowingRemoveConfirmation = false

    private let gridColumns = [GridItem(.adaptive(minimum: 170, maximum: 230), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Backgrounds")
                .font(.title2.bold())

            itemCountRow

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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    choosePhotos()
                } label: {
                    Image(systemName: "photo.badge.plus")
                }
                .help("Add Photo")

                Button {
                    chooseFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .help("Add Folder")

                Button(role: .destructive) {
                    isShowingRemoveConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(!canRemoveSelected)
                .help("Remove Selected Background")
            }
        }
        .onAppear {
            refreshCollection()
        }
        .alert(
            "Remove Background?",
            isPresented: $isShowingRemoveConfirmation
        ) {
            Button("Remove", role: .destructive) {
                removeSelected()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Are you sure you want to remove this background image from Leaf?")
        }
    }

    private var itemCountRow: some View {
        HStack {
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
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(NSColor.separatorColor), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
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
        VStack(alignment: .leading, spacing: 0) {
            tilePreview(for: item.fileURL)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color(NSColor.separatorColor), lineWidth: isSelected ? 2 : 1)
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
                .frame(height: 110)
                .frame(maxWidth: .infinity)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            fallbackPreview
                .frame(height: 110)
                .frame(maxWidth: .infinity)
        }
        #else
        fallbackPreview
            .frame(height: 110)
            .frame(maxWidth: .infinity)
        #endif
    }

    private var fallbackPreview: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                Image(systemName: "photo")
                    .foregroundStyle(.secondary)
            )
    }

    private var canRemoveSelected: Bool {
        selectedBackgroundID != nil
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
