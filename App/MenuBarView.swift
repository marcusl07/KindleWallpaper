#if canImport(AppKit)
import AppKit
import Combine
import Foundation

@MainActor
final class MenuBarView: NSObject {
    typealias Action = () -> Void

    private enum Constants {
        static let quotePreviewCharacterLimit = 80
        static let emptyQuotePreview = "No quote selected yet"
    }

    let menu: NSMenu

    private let appState: AppState
    private let nextQuoteAction: Action
    private let openSettingsAction: Action
    private let quitAction: Action
    private var cancellables = Set<AnyCancellable>()

    private let quotePreviewItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let highlightCountItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

    init(
        appState: AppState,
        nextQuoteAction: @escaping Action,
        openSettingsAction: @escaping Action,
        quitAction: @escaping Action
    ) {
        self.appState = appState
        self.nextQuoteAction = nextQuoteAction
        self.openSettingsAction = openSettingsAction
        self.quitAction = quitAction
        self.menu = NSMenu()

        super.init()

        configureMenu()
        bindAppState()
    }

    private func configureMenu() {
        quotePreviewItem.isEnabled = false
        highlightCountItem.isEnabled = false

        let nextQuoteItem = NSMenuItem(
            title: "Next Quote",
            action: #selector(nextQuoteClicked),
            keyEquivalent: "n"
        )
        nextQuoteItem.target = self

        let openSettingsItem = NSMenuItem(
            title: "Open Settings...",
            action: #selector(openSettingsClicked),
            keyEquivalent: ","
        )
        openSettingsItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitClicked),
            keyEquivalent: "q"
        )
        quitItem.target = self

        menu.addItem(quotePreviewItem)
        menu.addItem(nextQuoteItem)
        menu.addItem(.separator())
        menu.addItem(openSettingsItem)
        menu.addItem(.separator())
        menu.addItem(highlightCountItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)

        refreshMenuLabels()
    }

    private func bindAppState() {
        appState.$currentQuotePreview
            .receive(on: RunLoop.main)
            .sink { [weak self] preview in
                self?.quotePreviewItem.title = Self.quotePreviewTitle(from: preview)
            }
            .store(in: &cancellables)

        appState.$totalHighlightCount
            .receive(on: RunLoop.main)
            .sink { [weak self] count in
                self?.highlightCountItem.title = Self.highlightCountTitle(from: count)
            }
            .store(in: &cancellables)
    }

    private func refreshMenuLabels() {
        quotePreviewItem.title = Self.quotePreviewTitle(from: appState.currentQuotePreview)
        highlightCountItem.title = Self.highlightCountTitle(from: appState.totalHighlightCount)
    }

    private static func quotePreviewTitle(from quote: String) -> String {
        let collapsedQuote = quote
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let previewBody: String
        if collapsedQuote.isEmpty {
            previewBody = Constants.emptyQuotePreview
        } else if collapsedQuote.count <= Constants.quotePreviewCharacterLimit {
            previewBody = collapsedQuote
        } else {
            let cutoffIndex = collapsedQuote.index(
                collapsedQuote.startIndex,
                offsetBy: Constants.quotePreviewCharacterLimit - 3
            )
            previewBody = "\(collapsedQuote[..<cutoffIndex])..."
        }

        return "Current quote: \(previewBody)"
    }

    private static func highlightCountTitle(from total: Int) -> String {
        "Highlights in library: \(total)"
    }

    @objc private func nextQuoteClicked() {
        nextQuoteAction()
    }

    @objc private func openSettingsClicked() {
        openSettingsAction()
    }

    @objc private func quitClicked() {
        quitAction()
    }
}
#endif
