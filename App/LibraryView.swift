import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var appState: AppState
    @State private var selectedSidebarItem: LibrarySidebarItem? = .quotes

    enum LibrarySidebarItem: String, Hashable, CaseIterable, Identifiable {
        case quotes = "Quotes"
        case books = "Books"
        case backgrounds = "Backgrounds"

        var id: String { rawValue }

        var iconName: String {
            switch self {
            case .quotes: return "quote.opening"
            case .books: return "book"
            case .backgrounds: return "photo"
            }
        }
    }

    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(LibrarySidebarItem.allCases, selection: $selectedSidebarItem) { item in
                NavigationLink(value: item) {
                    Label(item.rawValue, systemImage: item.iconName)
                }
            }
            .navigationTitle("Library")
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 300)
        } detail: {
            if let selectedSidebarItem {
                switch selectedSidebarItem {
                case .quotes:
                    QuotesLibraryWrapperView()
                case .books:
                    BooksListView()
                case .backgrounds:
                    BackgroundsListView()
                }
            } else {
                Text("Select an item from the sidebar")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, idealWidth: 900, maxWidth: .infinity, minHeight: 600, idealHeight: 600, maxHeight: .infinity)
    }
}

struct QuotesLibraryWrapperView: View {
    @EnvironmentObject private var appState: AppState
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            QuotesListView { highlightID in
                navigationPath.append(highlightID)
            }
            .navigationDestination(for: UUID.self) { highlightID in
                if let highlight = appState.loadHighlight(id: highlightID) {
                    QuoteDetailView(highlight: highlight)
                } else {
                    QuotesEmptyStateView(
                        title: "Quote Not Found",
                        systemImage: "quote.opening",
                        description: "This quote is no longer available."
                    )
                }
            }
        }
    }
}
