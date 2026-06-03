import SwiftUI
#if canImport(AppKit)
import AppKit
import UniformTypeIdentifiers
#endif

struct QuotesImportHeaderView: View {
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
            } else if appState.totalHighlightCount == 0 {
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
func chooseClippingsFile(for appState: AppState) {
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

private enum ImportRefreshPresentationModel {
    enum RefreshDecision: Equatable {
        case applySnapshot(LibrarySnapshot)
        case refreshLibraryState
    }

    static func refreshDecision(for librarySnapshot: LibrarySnapshot?) -> RefreshDecision {
        if let librarySnapshot {
            return .applySnapshot(librarySnapshot)
        }

        return .refreshLibraryState
    }
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
    switch ImportRefreshPresentationModel.refreshDecision(for: result.librarySnapshot) {
    case .applySnapshot(let librarySnapshot):
        appState.applyLibrarySnapshot(librarySnapshot)
    case .refreshLibraryState:
        appState.refreshLibraryState()
    }
    #else
    appState.setImportStatus("Import unavailable in this build.", isError: true)
    #endif
}

#if TESTING
enum SettingsImportFlowTestProbe {
    static func refreshDecision(
        for librarySnapshot: LibrarySnapshot?
    ) -> (mode: String, snapshot: LibrarySnapshot?) {
        switch ImportRefreshPresentationModel.refreshDecision(for: librarySnapshot) {
        case .applySnapshot(let librarySnapshot):
            return ("applySnapshot", librarySnapshot)
        case .refreshLibraryState:
            return ("refreshLibraryState", nil)
        }
    }
}
#endif
