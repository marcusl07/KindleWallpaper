import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct QuotesListRenderCompletionObserver: NSViewRepresentable {
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

struct QuotesFilterControlsContentMetrics: Equatable {
    let width: CGFloat
    let minX: CGFloat
}

struct QuotesFilterControlsViewportWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct QuotesFilterControlsContentMetricsPreferenceKey: PreferenceKey {
    static var defaultValue = QuotesFilterControlsContentMetrics(width: 0, minX: 0)

    static func reduce(value: inout QuotesFilterControlsContentMetrics, nextValue: () -> QuotesFilterControlsContentMetrics) {
        value = nextValue()
    }
}

struct QuotesFilterOverflowAffordance: View {
    let systemImage: String
    let alignment: Alignment

    var body: some View {
        ZStack(alignment: alignment) {
            Rectangle()
                .fill(gradient)
                .frame(width: 30)

            Image(systemName: systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: alignment)
        .accessibilityHidden(true)
    }

    private var gradient: LinearGradient {
        switch alignment {
        case .leading:
            return LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor), Color(nsColor: .windowBackgroundColor).opacity(0)],
                startPoint: .leading,
                endPoint: .trailing
            )
        default:
            return LinearGradient(
                colors: [Color(nsColor: .windowBackgroundColor).opacity(0), Color(nsColor: .windowBackgroundColor)],
                startPoint: .leading,
                endPoint: .trailing
            )
        }
    }
}

struct QuotesListRowModel: Identifiable, Equatable {
    let highlight: Highlight
    let previewText: String
    let bookTitleText: String
    let authorText: String

    var id: UUID { highlight.id }

    static func == (lhs: QuotesListRowModel, rhs: QuotesListRowModel) -> Bool {
        lhs.id == rhs.id
            && lhs.previewText == rhs.previewText
            && lhs.bookTitleText == rhs.bookTitleText
            && lhs.authorText == rhs.authorText
    }

    init(highlight: Highlight) {
        self.highlight = highlight
        self.previewText = QuotesListPresentationModel.previewText(for: highlight.quoteText)
        self.bookTitleText = QuotesListPresentationModel.bookTitleText(for: highlight)
        self.authorText = QuotesListPresentationModel.authorText(for: highlight)
    }
}

struct QuotesListRowView: View, Equatable {
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

struct QuotesNativeTableView: NSViewRepresentable {
    let rows: [QuotesListRowModel]
    @Binding var selectedHighlightIDs: Set<UUID>
    let isLoadingNextPage: Bool
    let onLoadMore: (UUID) -> Void
    let onNavigateToQuote: (UUID) -> Void
    let onSetWallpaper: (UUID) -> Void
    let onDeleteQuotes: ([UUID]) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = QuotesNativeTableScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .controlBackgroundColor

        let tableView = QuotesNativeTableViewControl()
        tableView.headerView = nil
        tableView.rowHeight = 68
        tableView.intercellSpacing = NSSize(width: 0, height: 0)
        tableView.style = .plain
        tableView.selectionHighlightStyle = .regular
        tableView.usesAlternatingRowBackgroundColors = false
        tableView.gridStyleMask = []
        tableView.allowsColumnReordering = false
        tableView.allowsColumnResizing = false
        tableView.allowsColumnSelection = false
        tableView.allowsMultipleSelection = true
        tableView.allowsEmptySelection = true
        tableView.dataSource = context.coordinator
        tableView.delegate = context.coordinator
        tableView.target = context.coordinator
        tableView.doubleAction = #selector(Coordinator.doubleClickRow(_:))
        tableView.onReturnPressed = { [weak coordinator = context.coordinator] in
            coordinator?.triggerDefaultAction()
        }
        tableView.onDeletePressed = { [weak coordinator = context.coordinator] in
            coordinator?.triggerDeleteAction()
        }

        let menu = NSMenu()
        menu.delegate = context.coordinator
        tableView.menu = menu

        let column = NSTableColumn(identifier: Coordinator.quoteColumnIdentifier)
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)

        scrollView.documentView = tableView
        scrollView.tableView = tableView
        context.coordinator.tableView = tableView
        context.coordinator.update(
            rows: rows,
            selectedHighlightIDs: $selectedHighlightIDs,
            isLoadingNextPage: isLoadingNextPage,
            onLoadMore: onLoadMore,
            onNavigateToQuote: onNavigateToQuote,
            onSetWallpaper: onSetWallpaper,
            onDeleteQuotes: onDeleteQuotes
        )
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.update(
            rows: rows,
            selectedHighlightIDs: $selectedHighlightIDs,
            isLoadingNextPage: isLoadingNextPage,
            onLoadMore: onLoadMore,
            onNavigateToQuote: onNavigateToQuote,
            onSetWallpaper: onSetWallpaper,
            onDeleteQuotes: onDeleteQuotes
        )
        (scrollView as? QuotesNativeTableScrollView)?.resizeQuoteColumn()
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate, NSMenuDelegate {
        static let quoteColumnIdentifier = NSUserInterfaceItemIdentifier("QuoteColumn")

        private static let quoteCellIdentifier = NSUserInterfaceItemIdentifier("QuoteCell")
        private static let loadingCellIdentifier = NSUserInterfaceItemIdentifier("LoadingCell")

        weak var tableView: NSTableView?

        private var rows: [QuotesListRowModel] = []
        private var selectedHighlightIDs: Binding<Set<UUID>> = .constant([])
        private var isLoadingNextPage = false
        private var onLoadMore: (UUID) -> Void = { _ in }
        private var onNavigateToQuote: (UUID) -> Void = { _ in }
        private var onSetWallpaper: (UUID) -> Void = { _ in }
        private var onDeleteQuotes: ([UUID]) -> Void = { _ in }
        private var isSyncingSelection = false

        func update(
            rows: [QuotesListRowModel],
            selectedHighlightIDs: Binding<Set<UUID>>,
            isLoadingNextPage: Bool,
            onLoadMore: @escaping (UUID) -> Void,
            onNavigateToQuote: @escaping (UUID) -> Void,
            onSetWallpaper: @escaping (UUID) -> Void,
            onDeleteQuotes: @escaping ([UUID]) -> Void
        ) {
            let shouldReload = self.rows != rows || self.isLoadingNextPage != isLoadingNextPage

            self.rows = rows
            self.selectedHighlightIDs = selectedHighlightIDs
            self.isLoadingNextPage = isLoadingNextPage
            self.onLoadMore = onLoadMore
            self.onNavigateToQuote = onNavigateToQuote
            self.onSetWallpaper = onSetWallpaper
            self.onDeleteQuotes = onDeleteQuotes

            guard let tableView else {
                return
            }

            if shouldReload {
                tableView.reloadData()
            }

            syncSelection(to: tableView)
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            rows.count + (isLoadingNextPage ? 1 : 0)
        }

        func tableView(
            _ tableView: NSTableView,
            viewFor tableColumn: NSTableColumn?,
            row rowIndex: Int
        ) -> NSView? {
            if rowIndex >= rows.count {
                return loadingView(for: tableView)
            }

            let row = rows[rowIndex]
            onLoadMore(row.id)

            let view = tableView.makeView(
                withIdentifier: Self.quoteCellIdentifier,
                owner: self
            ) as? QuotesNativeTableCellView ?? QuotesNativeTableCellView()
            view.identifier = Self.quoteCellIdentifier
            view.configure(with: row)
            return view
        }

        @objc func doubleClickRow(_ sender: NSTableView) {
            triggerDefaultAction()
        }

        func triggerDefaultAction() {
            guard let tableView else { return }
            let selectedRow = tableView.selectedRow
            guard rows.indices.contains(selectedRow) else {
                return
            }
            let highlightID = rows[selectedRow].id
            onNavigateToQuote(highlightID)
        }

        func tableViewSelectionDidChange(_ notification: Notification) {
            guard !isSyncingSelection,
                  let tableView = notification.object as? NSTableView else {
                return
            }

            selectedHighlightIDs.wrappedValue = Set(
                tableView.selectedRowIndexes.compactMap { rowIndex in
                    guard rows.indices.contains(rowIndex) else {
                        return nil
                    }

                    return rows[rowIndex].id
                }
            )
        }

        private func loadingView(for tableView: NSTableView) -> NSView {
            if let reusedView = tableView.makeView(
                withIdentifier: Self.loadingCellIdentifier,
                owner: self
            ) as? QuotesNativeLoadingCellView {
                return reusedView
            }

            let view = QuotesNativeLoadingCellView()
            view.identifier = Self.loadingCellIdentifier
            return view
        }

        private func syncSelection(to tableView: NSTableView) {
            isSyncingSelection = true
            defer { isSyncingSelection = false }

            let selectedIndexes = IndexSet(
                rows.enumerated().compactMap { index, row in
                    selectedHighlightIDs.wrappedValue.contains(row.id) ? index : nil
                }
            )
            guard selectedIndexes != tableView.selectedRowIndexes else {
                return
            }

            tableView.selectRowIndexes(selectedIndexes, byExtendingSelection: false)
        }

        private func deselectAll(in tableView: NSTableView) {
            isSyncingSelection = true
            tableView.deselectAll(nil)
            isSyncingSelection = false
        }

        func triggerDeleteAction() {
            guard let tableView else { return }
            let selectedRowIndexes = tableView.selectedRowIndexes
            let ids = selectedRowIndexes.compactMap { index -> UUID? in
                rows.indices.contains(index) ? rows[index].id : nil
            }
            guard !ids.isEmpty else { return }
            onDeleteQuotes(ids)
        }

        // MARK: - NSMenuDelegate

        func menuNeedsUpdate(_ menu: NSMenu) {
            menu.removeAllItems()

            guard let tableView else { return }
            let clickedRow = tableView.clickedRow

            if clickedRow >= 0 && !tableView.selectedRowIndexes.contains(clickedRow) {
                tableView.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }

            let selectedRowIndexes = tableView.selectedRowIndexes
            guard !selectedRowIndexes.isEmpty else { return }

            if selectedRowIndexes.count == 1 {
                let viewItem = NSMenuItem(title: "View Details", action: #selector(viewQuoteDetailsClicked), keyEquivalent: "")
                viewItem.target = self
                menu.addItem(viewItem)

                let setWallpaperItem = NSMenuItem(title: "Set as Wallpaper", action: #selector(setWallpaperClicked), keyEquivalent: "")
                setWallpaperItem.target = self
                menu.addItem(setWallpaperItem)

                menu.addItem(.separator())
            }

            let deleteTitle = selectedRowIndexes.count == 1 ? "Delete Quote..." : "Delete Selected Quotes..."
            let deleteItem = NSMenuItem(title: deleteTitle, action: #selector(deleteQuotesClicked), keyEquivalent: "")
            deleteItem.target = self
            menu.addItem(deleteItem)

            menu.addItem(.separator())

            let copyItem = NSMenuItem(title: "Copy Quote", action: #selector(copyQuoteClicked), keyEquivalent: "")
            copyItem.target = self
            menu.addItem(copyItem)
        }

        @objc func viewQuoteDetailsClicked(_ sender: Any) {
            guard let tableView else { return }
            let row = tableView.selectedRow
            guard rows.indices.contains(row) else { return }
            onNavigateToQuote(rows[row].id)
        }

        @objc func setWallpaperClicked(_ sender: Any) {
            guard let tableView else { return }
            let row = tableView.selectedRow
            guard rows.indices.contains(row) else { return }
            onSetWallpaper(rows[row].id)
        }

        @objc func deleteQuotesClicked(_ sender: Any) {
            triggerDeleteAction()
        }

        @objc func copyQuoteClicked(_ sender: Any) {
            guard let tableView else { return }
            let row = tableView.selectedRow
            guard rows.indices.contains(row) else { return }
            let quoteText = rows[row].highlight.quoteText
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(quoteText, forType: .string)
        }
    }
}

final class QuotesNativeTableScrollView: NSScrollView {
    weak var tableView: NSTableView?

    override var fittingSize: NSSize {
        NSSize(width: 100, height: 100)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        resizeQuoteColumn()
    }

    func resizeQuoteColumn() {
        guard let tableView,
              let column = tableView.tableColumns.first else {
            return
        }

        column.width = contentSize.width
    }
}

final class QuotesNativeTableViewControl: NSTableView {
    var onReturnPressed: (() -> Void)?
    var onDeletePressed: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76 { // Return or Enter key code
            onReturnPressed?()
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 { // Delete or Forward Delete key code
            onDeletePressed?()
            return
        }
        super.keyDown(with: event)
    }
}

final class QuotesNativeTableCellView: NSTableCellView {
    private let previewTextField = NSTextField(labelWithString: "")
    private let bookTitleTextField = NSTextField(labelWithString: "")
    private let separatorTextField = NSTextField(labelWithString: "•")
    private let authorTextField = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildView()
    }

    func configure(with row: QuotesListRowModel) {
        previewTextField.stringValue = row.previewText
        bookTitleTextField.stringValue = row.bookTitleText
        authorTextField.stringValue = row.authorText
        toolTip = "\(row.previewText)\n\(row.bookTitleText) • \(row.authorText)"
    }

    private func buildView() {
        wantsLayer = true

        previewTextField.font = .preferredFont(forTextStyle: .body)
        previewTextField.lineBreakMode = .byTruncatingTail
        previewTextField.maximumNumberOfLines = 2
        previewTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        bookTitleTextField.font = .preferredFont(forTextStyle: .callout)
        bookTitleTextField.lineBreakMode = .byTruncatingTail
        bookTitleTextField.maximumNumberOfLines = 1
        bookTitleTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        separatorTextField.textColor = .tertiaryLabelColor

        authorTextField.font = .preferredFont(forTextStyle: .callout)
        authorTextField.textColor = .secondaryLabelColor
        authorTextField.lineBreakMode = .byTruncatingTail
        authorTextField.maximumNumberOfLines = 1
        authorTextField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let metadataStack = NSStackView(views: [
            bookTitleTextField,
            separatorTextField,
            authorTextField
        ])
        metadataStack.orientation = .horizontal
        metadataStack.alignment = .firstBaseline
        metadataStack.spacing = 6
        metadataStack.distribution = .fill

        let contentStack = NSStackView(views: [
            previewTextField,
            metadataStack
        ])
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 6
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 12),
            contentStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            contentStack.centerYAnchor.constraint(equalTo: centerYAnchor),
            previewTextField.trailingAnchor.constraint(equalTo: contentStack.trailingAnchor),
            metadataStack.trailingAnchor.constraint(lessThanOrEqualTo: contentStack.trailingAnchor)
        ])
    }
}

final class QuotesNativeLoadingCellView: NSTableCellView {
    private let progressIndicator = NSProgressIndicator()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        buildView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        buildView()
    }

    private func buildView() {
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isIndeterminate = true
        progressIndicator.startAnimation(nil)
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(progressIndicator)

        NSLayoutConstraint.activate([
            progressIndicator.centerXAnchor.constraint(equalTo: centerXAnchor),
            progressIndicator.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
}

struct QuotesLibrarySearchField: NSViewRepresentable {
    let committedSearchText: String
    let placeholder: String
    let onTextChanged: (String) -> Void

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField(frame: .zero)
        searchField.placeholderString = placeholder
        searchField.stringValue = committedSearchText
        searchField.delegate = context.coordinator
        searchField.sendsSearchStringImmediately = true
        searchField.focusRingType = .default
        searchField.controlSize = .large
        return searchField
    }

    func updateNSView(_ searchField: NSSearchField, context: Context) {
        searchField.placeholderString = placeholder
        context.coordinator.onTextChanged = onTextChanged

        guard searchField.currentEditor() == nil,
              searchField.stringValue != committedSearchText else {
            return
        }

        searchField.stringValue = committedSearchText
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onTextChanged: onTextChanged)
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var onTextChanged: (String) -> Void

        init(onTextChanged: @escaping (String) -> Void) {
            self.onTextChanged = onTextChanged
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else {
                return
            }

            onTextChanged(searchField.stringValue)
        }
    }
}
