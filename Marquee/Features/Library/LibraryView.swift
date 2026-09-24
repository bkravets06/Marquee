import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - MediaKindFilter

/// Kind filter applied to the library list (toolbar "Filter" menu).
enum MediaKindFilter: String, CaseIterable, Identifiable {
    case all
    case shows
    case movies

    var id: String { rawValue }

    /// Menu title ("All", "Shows", "Movies").
    var title: String {
        switch self {
        case .all: return "All"
        case .shows: return "Shows"
        case .movies: return "Movies"
        }
    }

    var symbolName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .shows: return MediaKind.show.symbolName
        case .movies: return MediaKind.movie.symbolName
        }
    }

    /// Whether `item` passes the filter.
    func matches(_ item: MediaItem) -> Bool {
        switch self {
        case .all: return true
        case .shows: return item.isShow
        case .movies: return item.isMovie
        }
    }
}

// MARK: - LibrarySort

/// Sort order of the library list (toolbar "Sort By" menu).
enum LibrarySort: String, CaseIterable, Identifiable {
    case recentlyUpdated
    case title
    case dateAdded

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recentlyUpdated: return "Recently Updated"
        case .title: return "Title"
        case .dateAdded: return "Date Added"
        }
    }

    var symbolName: String {
        switch self {
        case .recentlyUpdated: return "clock"
        case .title: return "textformat"
        case .dateAdded: return "calendar.badge.plus"
        }
    }

    /// `items` in this order.
    func sorted(_ items: [MediaItem]) -> [MediaItem] {
        switch self {
        case .recentlyUpdated:
            return items.sorted { $0.updatedAt > $1.updatedAt }
        case .title:
            return items.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .dateAdded:
            return items.sorted { $0.addedAt > $1.addedAt }
        }
    }
}

// MARK: - LibraryView

/// The Library tab: a segmented Watching / Watchlist / Watched list with an
/// "Up Next" strip, filter and sort menus, custom-item creation and Settings.
struct LibraryView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(Navigator.self) private var navigator
    @Environment(\.modelContext) private var modelContext

    @State private var selectedStatus: WatchStatus = .watching
    @State private var kindFilter: MediaKindFilter = .all
    @State private var sort: LibrarySort = .recentlyUpdated
    @State private var showingSettings = false
    @State private var customFormKind: MediaKind?
    @State private var markCount = 0

    init() {}

    // MARK: Body

    var body: some View {
        @Bindable var navigator = navigator
        NavigationStack(path: $navigator.libraryPath) {
            libraryList
                .navigationTitle("Library")
                .navigationDestination(for: LibraryRoute.self) { route in
                    destination(for: route)
                }
                .toolbar {
                    toolbarContent
                }
                .sheet(isPresented: $showingSettings) {
                    SettingsView()
                }
                .sheet(item: $customFormKind) { kind in
                    CustomItemForm(item: nil, prefilledTitle: nil, kind: kind)
                }
        }
    }

    // MARK: List

    private var libraryList: some View {
        List {
            Section {
                statusPicker
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            LibraryListView(
                status: selectedStatus,
                kindFilter: $kindFilter,
                sort: sort,
                onMarked: { markCount += 1 }
            )
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(.compact)
        .refreshable {
            await refreshLibrary()
        }
        .sensoryFeedback(.success, trigger: markCount)
    }

    private var statusPicker: some View {
        Picker("Status", selection: $selectedStatus.animation()) {
            ForEach(WatchStatus.allCases) { status in
                Text(status.displayName).tag(status)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private func destination(for route: LibraryRoute) -> some View {
        switch route {
        case .item(let id):
            MediaDetailView(reference: .library(id))
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            filterMenu
            addMenu
            settingsButton
        }
    }

    private var filterMenu: some View {
        Menu {
            Section("Filter") {
                Picker("Filter", selection: $kindFilter.animation()) {
                    ForEach(MediaKindFilter.allCases) { filter in
                        Label(filter.title, systemImage: filter.symbolName)
                            .tag(filter)
                    }
                }
                .pickerStyle(.inline)
            }
            Section("Sort By") {
                Picker("Sort By", selection: $sort.animation()) {
                    ForEach(LibrarySort.allCases) { option in
                        Label(option.title, systemImage: option.symbolName)
                            .tag(option)
                    }
                }
                .pickerStyle(.inline)
            }
        } label: {
            Label("Filter and Sort", systemImage: filterSymbolName)
        }
    }

    /// Filled symbol while a non-default filter or sort is active.
    private var filterSymbolName: String {
        let isActive = kindFilter != .all || sort != .recentlyUpdated
        return isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle"
    }

    private var addMenu: some View {
        Menu {
            Button("Add Custom Show…", systemImage: "tv") {
                customFormKind = .show
            }
            Button("Add Custom Movie…", systemImage: "film") {
                customFormKind = .movie
            }
        } label: {
            Label("Add", systemImage: "plus")
        }
    }

    private var settingsButton: some View {
        Button("Settings", systemImage: "gearshape") {
            showingSettings = true
        }
    }

    // MARK: Refresh

    /// Pull to refresh: re-fetch every eligible show from TMDB and re-sync reminders.
    private func refreshLibrary() async {
        let refresher = LibraryRefresher(environment: appEnvironment, context: modelContext)
        await refresher.refreshAll(force: true)
    }
}

// MARK: - LibraryListView

/// The sections for one status segment. It lives inside `LibraryView`'s `List`
/// so the segmented picker above it keeps its identity while the query changes.
///
/// `@Query` cannot change its predicate after the fact, so the query is built
/// in `init` from `status`; SwiftUI re-runs the initializer whenever the parent
/// passes a different status. Kind filtering and sorting happen in memory.
struct LibraryListView: View {

    let status: WatchStatus
    let sort: LibrarySort
    let onMarked: () -> Void

    @Binding var kindFilter: MediaKindFilter

    @Environment(Navigator.self) private var navigator
    @Query private var items: [MediaItem]

    init(status: WatchStatus, kindFilter: Binding<MediaKindFilter>, sort: LibrarySort, onMarked: @escaping () -> Void) {
        self.status = status
        self.sort = sort
        self.onMarked = onMarked
        self._kindFilter = kindFilter

        let raw = status.rawValue
        self._items = Query(
            filter: #Predicate<MediaItem> { item in item.statusRaw == raw },
            sort: [SortDescriptor(\MediaItem.updatedAt, order: .reverse)]
        )
    }

    // MARK: Derived data

    /// Items after the kind filter and sort.
    private var visibleItems: [MediaItem] {
        sort.sorted(items.filter { kindFilter.matches($0) })
    }

    /// Shows whose next episode airs within a week, soonest first.
    private var upNextItems: [MediaItem] {
        items
            .filter { $0.isShow && $0.nextEpisodeAirDate != nil && $0.airsWithinDays(7) }
            .sorted { ($0.nextEpisodeAirDate ?? .distantFuture) < ($1.nextEpisodeAirDate ?? .distantFuture) }
    }

    private var showsUpNext: Bool {
        status == .watching && kindFilter != .movies && !upNextItems.isEmpty
    }

    // MARK: Body

    var body: some View {
        if visibleItems.isEmpty {
            emptySection
        } else {
            if showsUpNext {
                upNextSection
            }
            rowsSection
        }
    }

    private var upNextSection: some View {
        Section {
            UpNextStrip(items: upNextItems)
        }
        .listRowInsets(EdgeInsets())
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    private var rowsSection: some View {
        Section {
            ForEach(visibleItems) { item in
                LibraryRow(item: item, onMarked: onMarked)
            }
        }
    }

    // MARK: Empty states

    private var emptySection: some View {
        Section {
            emptyState
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        }
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
    }

    @ViewBuilder
    private var emptyState: some View {
        if kindFilter != .all, !items.isEmpty {
            ContentUnavailableView {
                Label(filteredEmptyTitle, systemImage: kindFilter.symbolName)
            } description: {
                Text("Nothing in \(status.displayName) matches this filter.")
            } actions: {
                Button("Show All") {
                    withAnimation {
                        kindFilter = .all
                    }
                }
                .buttonStyle(.bordered)
            }
        } else {
            ContentUnavailableView {
                Label(emptyTitle, systemImage: status.symbolName)
            } description: {
                Text(emptyDescription)
            } actions: {
                Button {
                    navigator.tab = emptyDestination
                } label: {
                    Label(emptyButtonTitle, systemImage: emptyButtonSymbol)
                        .foregroundStyle(.black)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var filteredEmptyTitle: String {
        "No \(kindFilter.title)"
    }

    private var emptyTitle: String {
        switch status {
        case .watching: return "Nothing in Progress"
        case .watchlist: return "Your Watchlist Is Empty"
        case .watched: return "Nothing Watched Yet"
        }
    }

    private var emptyDescription: String {
        switch status {
        case .watching: return "Shows and movies you start watching will show up here."
        case .watchlist: return "Save shows and movies you want to watch later."
        case .watched: return "Everything you finish is kept here."
        }
    }

    private var emptyButtonTitle: String {
        switch status {
        case .watching, .watchlist: return "Find Something to Watch"
        case .watched: return "Search for a Title"
        }
    }

    private var emptyButtonSymbol: String {
        switch status {
        case .watching, .watchlist: return "sparkles"
        case .watched: return "magnifyingglass"
        }
    }

    private var emptyDestination: AppTab {
        switch status {
        case .watching, .watchlist: return .discover
        case .watched: return .search
        }
    }
}

// MARK: - Preview

#Preview {
    LibraryView()
        .modelContainer(PreviewData.container)
        .environment(AppEnvironment.shared)
        .environment(Navigator.shared)
}
