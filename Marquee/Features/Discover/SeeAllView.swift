import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - SeeAllView

/// Every row of one Discover section in a paging grid. Pushed from a
/// carousel's "See All" link; the carousel hands over the rows it already has
/// so the grid appears instantly and paging continues from the next page.
struct SeeAllView: View {

    let section: DiscoverSectionKind
    private let initialState: DiscoverSectionState?

    @Environment(AppEnvironment.self) private var appEnvironment
    @State private var model = DiscoverModel()

    private let cardWidth: CGFloat = 110
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12, alignment: .top)]

    init(section: DiscoverSectionKind, initialState: DiscoverSectionState? = nil) {
        self.section = section
        self.initialState = initialState
    }

    // MARK: Body

    var body: some View {
        content
            .navigationTitle(section.title)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: appEnvironment.client == nil) {
                await loadInitial()
            }
    }

    private var state: DiscoverSectionState {
        model.state(for: section)
    }

    @ViewBuilder
    private var content: some View {
        if appEnvironment.client == nil {
            noCredentialsView
        } else if state.showsPlaceholder {
            placeholderGrid
        } else if state.items.isEmpty, let message = state.errorMessage {
            failureView(message: message)
        } else if state.items.isEmpty {
            emptyView
        } else {
            grid
        }
    }

    // MARK: Grid

    private var grid: some View {
        ScrollView {
            VStack(spacing: 0) {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(state.items, id: \.key) { summary in
                        DiscoverCard(summary: summary, width: cardWidth)
                            .onAppear {
                                loadMoreIfNeeded(after: summary)
                            }
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                footer
            }
            .padding(.bottom, 24)
        }
        .refreshable {
            await refresh()
        }
    }

    @ViewBuilder
    private var footer: some View {
        if state.isLoadingMore {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityLabel("Loading more")
        } else if let message = state.pagingErrorMessage {
            ErrorRetryView(message: message, retry: { loadMore() })
                .padding(.horizontal)
                .padding(.vertical, 8)
        }
    }

    private var placeholderGrid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 16) {
                ForEach(0..<12, id: \.self) { _ in
                    MediaCardPlaceholder(width: cardWidth)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)
        }
        .scrollDisabled(true)
    }

    // MARK: Empty states

    private var noCredentialsView: some View {
        ContentUnavailableView(
            "Connect to TMDB",
            systemImage: "key.fill",
            description: Text("Add a TMDB API key in Settings to browse this list.")
        )
    }

    private var emptyView: some View {
        ContentUnavailableView(
            "Nothing Here Right Now",
            systemImage: section.symbolName,
            description: Text(section.emptyDescription)
        )
    }

    private func failureView(message: String) -> some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("Retry") {
                Task {
                    await refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Loading

    private func loadInitial() async {
        guard let client = appEnvironment.client else { return }
        if let initialState, !state.hasLoaded {
            model.seed(section: section, with: initialState)
        }
        await model.load(section: section, client: client, force: false)
    }

    private func refresh() async {
        guard let client = appEnvironment.client else { return }
        await model.load(section: section, client: client, force: true)
    }

    private func loadMoreIfNeeded(after summary: MediaSummary) {
        guard summary.key == state.items.last?.key else { return }
        loadMore()
    }

    private func loadMore() {
        guard let client = appEnvironment.client else { return }
        Task {
            await model.loadMore(section: section, client: client)
        }
    }
}

// MARK: - Preview

private func previewSeededState() -> DiscoverSectionState {
    var state = DiscoverSectionState()
    state.items = PreviewData.sampleSummaries
    state.lastLoadedPage = 1
    state.totalPages = 4
    return state
}

#Preview("See All") {
    NavigationStack {
        SeeAllView(section: .trendingToday, initialState: previewSeededState())
    }
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
    .modelContainer(PreviewData.container)
}
