import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - SearchView

/// The Search tab: a debounced TMDB search with All / Shows / Movies scopes,
/// quick-add from the results, and a "Trending This Week" grid while the
/// query is empty. Without a TMDB credential it points to Settings.
struct SearchView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

    @State private var model = SearchModel()
    @State private var isShowingSettings = false
    @State private var isShowingCustomForm = false
    @State private var addCount = 0

    init() {}

    // MARK: Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Search")
                .navigationDestination(for: MediaReference.self) { reference in
                    MediaDetailView(reference: reference)
                }
                .searchable(
                    text: $model.query,
                    placement: .navigationBarDrawer(displayMode: .always),
                    prompt: "Shows, Movies"
                )
                .searchScopes($model.scope) {
                    ForEach(SearchScope.allCases) { scope in
                        Text(scope.title).tag(scope)
                    }
                }
                .onSubmit(of: .search) {
                    model.search(client: appEnvironment.client, immediate: true)
                }
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView()
                }
                .sheet(isPresented: $isShowingCustomForm) {
                    CustomItemForm(prefilledTitle: customPrefill, kind: model.scope.kind ?? .show)
                }
        }
        .onChange(of: model.query) { _, _ in
            model.search(client: appEnvironment.client)
        }
        .onChange(of: model.scope) { _, _ in
            model.search(client: appEnvironment.client)
        }
        .task(id: hasClient) {
            await clientDidChange()
        }
        .sensoryFeedback(.success, trigger: addCount)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !hasClient {
            noCredentialsView
        } else if model.isSearching {
            SearchResultsList(
                model: model,
                client: appEnvironment.client,
                onAdd: { summary, status in add(summary, status: status) },
                onAddCustom: { isShowingCustomForm = true }
            )
        } else {
            TrendingGrid(
                model: model,
                onRetry: { retryTrending() },
                onRefresh: { await refreshTrending() },
                onAdd: { summary, status in add(summary, status: status) }
            )
        }
    }

    private var noCredentialsView: some View {
        ContentUnavailableView {
            Label("Connect to TMDB", systemImage: "key.fill")
        } description: {
            Text("Add your TMDB API key or read access token to search for shows and movies.")
        } actions: {
            Button("Open Settings") {
                isShowingSettings = true
            }
            .buttonStyle(.borderedProminent)
            Button("Add a Custom Title") {
                isShowingCustomForm = true
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: Derived

    private var hasClient: Bool {
        appEnvironment.client != nil
    }

    /// The query, if any, used to prefill the custom item form.
    private var customPrefill: String? {
        let text = model.trimmedQuery
        return text.isEmpty ? nil : text
    }

    // MARK: Actions

    /// Runs when the view appears and whenever a credential is added or removed.
    private func clientDidChange() async {
        guard hasClient else {
            model.reset()
            return
        }
        if model.isSearching {
            model.search(client: appEnvironment.client, immediate: true)
        }
        await model.loadTrending(client: appEnvironment.client)
    }

    private func add(_ summary: MediaSummary, status: WatchStatus) {
        let store = LibraryStore(context: modelContext)
        store.add(summary, status: status)
        addCount += 1
    }

    private func retryTrending() {
        Task {
            await model.loadTrending(client: appEnvironment.client, force: true)
        }
    }

    private func refreshTrending() async {
        await model.loadTrending(client: appEnvironment.client, force: true)
    }
}

// MARK: - SearchResultsList

/// The results for a non-empty query: placeholders while loading, the rows
/// (paging at the end), a no-results state with a custom-title shortcut, and
/// inline retry on errors. Library membership comes from a `@Query` so rows
/// update the moment something is added.
private struct SearchResultsList: View {

    let model: SearchModel
    let client: TMDBClient?
    let onAdd: (MediaSummary, WatchStatus) -> Void
    let onAddCustom: () -> Void

    @Query private var libraryItems: [MediaItem]

    // MARK: Body

    var body: some View {
        if let message = model.errorMessage, model.results.isEmpty {
            failureView(message: message)
        } else if model.results.isEmpty, model.isLoading || !model.hasSearched {
            placeholderList
        } else if model.results.isEmpty {
            noResultsView
        } else {
            resultsList
        }
    }

    // MARK: Library lookup

    /// Library status keyed by `MediaSummary.key` ("show-123").
    private var statusByKey: [String: WatchStatus] {
        var map: [String: WatchStatus] = [:]
        for item in libraryItems {
            guard let tmdbID = item.tmdbID else { continue }
            map["\(item.kindRaw)-\(tmdbID)"] = item.status
        }
        return map
    }

    // MARK: Results

    private var resultsList: some View {
        List {
            if let message = model.errorMessage {
                Section {
                    ErrorRetryView(message: message, retry: { retry() })
                        .listRowSeparator(.hidden)
                }
            }
            Section {
                ForEach(model.results, id: \.key) { summary in
                    resultRow(for: summary)
                }
            }
            footer
        }
        .listStyle(.plain)
        .overlay(alignment: .top) {
            if model.isLoading {
                searchingBadge
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.isLoading)
    }

    private func resultRow(for summary: MediaSummary) -> some View {
        NavigationLink(value: MediaReference.tmdb(id: summary.id, kind: summary.kind)) {
            SearchResultRow(
                summary: summary,
                status: statusByKey[summary.key],
                onAdd: { status in onAdd(summary, status) }
            )
        }
        .onAppear {
            loadMoreIfNeeded(after: summary)
        }
    }

    @ViewBuilder
    private var footer: some View {
        if model.isLoadingMore {
            Section {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowSeparator(.hidden)
                    .accessibilityLabel("Loading more results")
            }
        } else if let message = model.pagingErrorMessage {
            Section {
                ErrorRetryView(message: message, retry: { loadMore() })
                    .listRowSeparator(.hidden)
            }
        }
    }

    private var searchingBadge: some View {
        HStack(spacing: 8) {
            ProgressView()
                .controlSize(.small)
            Text("Searching…")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.regularMaterial, in: Capsule())
        .padding(.top, 12)
        .transition(.opacity.combined(with: .move(edge: .top)))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Searching")
    }

    // MARK: Loading and empty states

    private var placeholderList: some View {
        List {
            ForEach(0..<8, id: \.self) { index in
                SearchResultRow(
                    summary: SearchResultRow.placeholderSummary(index),
                    status: nil,
                    onAdd: { _ in }
                )
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .disabled(true)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }

    private var noResultsView: some View {
        ContentUnavailableView {
            Label(noResultsTitle, systemImage: "magnifyingglass")
        } description: {
            Text("Check the spelling or try a new search.")
        } actions: {
            Button(addCustomTitle, action: onAddCustom)
                .buttonStyle(.borderedProminent)
        }
    }

    private func failureView(message: String) -> some View {
        ContentUnavailableView {
            Label("Unable to Search", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry", action: retry)
                .buttonStyle(.borderedProminent)
        }
    }

    private var noResultsTitle: String {
        "No Results for \u{201C}\(model.trimmedQuery)\u{201D}"
    }

    private var addCustomTitle: String {
        "Add \u{201C}\(model.trimmedQuery)\u{201D} as a Custom Title"
    }

    // MARK: Actions

    private func retry() {
        model.retry(client: client)
    }

    private func loadMore() {
        model.loadMore(client: client)
    }

    private func loadMoreIfNeeded(after summary: MediaSummary) {
        guard summary.key == model.results.last?.key else { return }
        loadMore()
    }
}

// MARK: - SearchResultRow

/// One search result: 50×75 poster, title, "2019 · Show" caption and, on the
/// trailing edge, either the item's library status or a `plus.circle`
/// quick-add menu.
///
/// API:
///   SearchResultRow(summary: MediaSummary, status: WatchStatus?, onAdd: @escaping (WatchStatus) -> Void)
struct SearchResultRow: View {

    let summary: MediaSummary
    let status: WatchStatus?
    let onAdd: (WatchStatus) -> Void

    init(summary: MediaSummary, status: WatchStatus?, onAdd: @escaping (WatchStatus) -> Void) {
        self.summary = summary
        self.status = status
        self.onAdd = onAdd
    }

    // MARK: Body

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PosterView(summary: summary, width: 50, cornerRadius: 6)
            textBlock
            Spacer(minLength: 8)
            trailing
        }
        .padding(.vertical, 4)
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(summary.title)
                .font(.headline)
                .lineLimit(2)
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if !genreText.isEmpty {
                Text(genreText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var trailing: some View {
        if let status {
            Label(status.displayName, systemImage: status.symbolName)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .labelStyle(.titleAndIcon)
                .accessibilityLabel("In library: \(status.displayName)")
        } else {
            Menu {
                QuickAddMenuItems(current: nil, onSelect: onAdd)
            } label: {
                Image(systemName: "plus.circle")
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .accessibilityLabel("Add \(summary.title) to Library")
        }
    }

    // MARK: Text

    /// "2019 · Show"
    private var caption: String {
        MediaCard.caption(year: summary.year, kind: summary.kind)
    }

    /// Up to two genre names, "Drama · Mystery".
    private var genreText: String {
        summary.genreNames.prefix(2).joined(separator: " · ")
    }

    // MARK: Placeholder

    /// A fake row used, redacted, while results load.
    static func placeholderSummary(_ index: Int) -> MediaSummary {
        MediaSummary(
            id: -(index + 1),
            kind: index.isMultiple(of: 2) ? .show : .movie,
            title: index.isMultiple(of: 3) ? "A Longer Placeholder Title" : "Placeholder Title",
            overview: "",
            posterPath: nil,
            backdropPath: nil,
            releaseDate: CivilDate(year: 2024, month: 1, day: 1),
            voteAverage: 0,
            voteCount: 0,
            popularity: 0,
            genreIDs: [18, 35],
            originalLanguage: nil
        )
    }
}

// MARK: - QuickAddMenuItems

/// "Start Watching" / "Add to Watchlist" / "Mark Watched" rows for a menu.
/// The row matching `current` shows a checkmark.
private struct QuickAddMenuItems: View {

    let current: WatchStatus?
    let onSelect: (WatchStatus) -> Void

    /// Menu order.
    static let order: [WatchStatus] = [.watching, .watchlist, .watched]

    static func title(for status: WatchStatus) -> String {
        switch status {
        case .watching: return "Start Watching"
        case .watchlist: return "Add to Watchlist"
        case .watched: return "Mark Watched"
        }
    }

    var body: some View {
        ForEach(QuickAddMenuItems.order) { status in
            Button {
                onSelect(status)
            } label: {
                Label(
                    QuickAddMenuItems.title(for: status),
                    systemImage: current == status ? "checkmark" : status.symbolName
                )
            }
        }
    }
}

// MARK: - LibraryQuickAddMenuItems

/// `QuickAddMenuItems` that looks up the item's library status when the menu
/// is built, so the lookup only runs on presentation.
private struct LibraryQuickAddMenuItems: View {

    let summary: MediaSummary
    let onSelect: (WatchStatus) -> Void

    @Environment(\.modelContext) private var modelContext

    var body: some View {
        QuickAddMenuItems(
            current: LibraryStore(context: modelContext).status(of: summary),
            onSelect: onSelect
        )
    }
}

// MARK: - TrendingGrid

/// "Trending This Week" for the empty-query state: an adaptive grid of
/// `MediaCard`s with redacted placeholders, inline retry and pull to refresh.
private struct TrendingGrid: View {

    let model: SearchModel
    let onRetry: () -> Void
    let onRefresh: () async -> Void
    let onAdd: (MediaSummary, WatchStatus) -> Void

    private static let cardWidth: CGFloat = 110
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .top)]

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                gridContent
            }
            .padding(.horizontal)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .refreshable {
            await onRefresh()
        }
    }

    private var header: some View {
        Text("Trending This Week")
            .font(.title3.bold())
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder
    private var gridContent: some View {
        if !model.trending.isEmpty {
            grid
        } else if showsPlaceholder {
            placeholderGrid
        } else if let message = model.trendingErrorMessage {
            ErrorRetryView(message: message, retry: onRetry)
        } else {
            Text("Nothing is trending right now.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var showsPlaceholder: Bool {
        if model.isLoadingTrending { return true }
        return !model.hasLoadedTrending && model.trendingErrorMessage == nil
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(model.trending, id: \.key) { summary in
                TrendingCard(summary: summary, width: TrendingGrid.cardWidth, onAdd: onAdd)
            }
        }
    }

    private var placeholderGrid: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(0..<9, id: \.self) { _ in
                MediaCardPlaceholder(width: TrendingGrid.cardWidth)
            }
        }
    }
}

// MARK: - TrendingCard

/// A tappable `MediaCard` that pushes the detail screen and offers quick-add
/// actions in its context menu.
private struct TrendingCard: View {

    let summary: MediaSummary
    let width: CGFloat
    let onAdd: (MediaSummary, WatchStatus) -> Void

    var body: some View {
        NavigationLink(value: MediaReference.tmdb(id: summary.id, kind: summary.kind)) {
            MediaCard(summary: summary, width: width)
        }
        .buttonStyle(.plain)
        .contextMenu {
            LibraryQuickAddMenuItems(summary: summary) { status in
                onAdd(summary, status)
            }
        }
    }
}

// MARK: - Preview

#Preview {
    SearchView()
        .environment(AppEnvironment.shared)
        .environment(Navigator.shared)
        .modelContainer(PreviewData.container)
}

#Preview("Result rows") {
    NavigationStack {
        List {
            SearchResultRow(summary: PreviewData.sampleSummary, status: .watching, onAdd: { _ in })
            SearchResultRow(summary: PreviewData.sampleMovieSummary, status: nil, onAdd: { _ in })
            SearchResultRow(summary: SearchResultRow.placeholderSummary(0), status: nil, onAdd: { _ in })
                .redacted(reason: .placeholder)
        }
        .listStyle(.plain)
        .navigationTitle("Search")
    }
    .modelContainer(PreviewData.container)
}
