import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - MediaCarousel
//
// One Discover section: a header (title + optional "See All" link) above a
// horizontally scrolling, view-aligned row of `MediaCard`s. Shows a redacted
// placeholder while loading, an inline retry on failure and a quiet note when
// TMDB returns nothing.
//
// API:
//   MediaCarousel(title:state:onRetry:seeAll:)   // seeAll builds the See All destination
//   MediaCarousel(title:state:onRetry:)          // no See All link

/// Card width used by every Discover carousel.
private let carouselCardWidth: CGFloat = 120

/// Horizontal poster carousel for one Discover section.
struct MediaCarousel<SeeAll: View>: View {

    let title: String
    let state: DiscoverSectionState
    let onRetry: () -> Void
    private let seeAll: (() -> SeeAll)?

    init(
        title: String,
        state: DiscoverSectionState,
        onRetry: @escaping () -> Void,
        @ViewBuilder seeAll: @escaping () -> SeeAll
    ) {
        self.title = title
        self.state = state
        self.onRetry = onRetry
        self.seeAll = seeAll
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            content
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.bold())
                .accessibilityAddTraits(.isHeader)
            Spacer()
            if let seeAll, !state.items.isEmpty {
                NavigationLink("See All") {
                    seeAll()
                }
                .accessibilityLabel("See all \(title)")
            }
        }
        .padding(.horizontal)
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !state.items.isEmpty {
            cards
        } else if state.showsPlaceholder {
            CarouselPlaceholder(count: 5, width: carouselCardWidth)
        } else if let message = state.errorMessage {
            ErrorRetryView(message: message, retry: onRetry)
                .padding(.horizontal)
        } else {
            emptyNote
        }
    }

    private var cards: some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 12) {
                ForEach(state.items, id: \.key) { summary in
                    DiscoverCard(summary: summary, width: carouselCardWidth)
                }
            }
            .scrollTargetLayout()
        }
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, 16, for: .scrollContent)
        .scrollTargetBehavior(.viewAligned)
    }

    private var emptyNote: some View {
        Text("Nothing here right now.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }
}

// MARK: - Without See All

extension MediaCarousel where SeeAll == EmptyView {

    /// A carousel with no "See All" link.
    init(title: String, state: DiscoverSectionState, onRetry: @escaping () -> Void) {
        self.title = title
        self.state = state
        self.onRetry = onRetry
        self.seeAll = nil
    }
}

// MARK: - DiscoverCard

/// A tappable `MediaCard` that pushes `MediaDetailView` and offers quick-add
/// actions in its context menu. Shared by the carousels and the See All grid.
struct DiscoverCard: View {

    let summary: MediaSummary
    let width: CGFloat

    @Environment(\.modelContext) private var modelContext
    @State private var addCount = 0

    init(summary: MediaSummary, width: CGFloat = 120) {
        self.summary = summary
        self.width = width
    }

    var body: some View {
        NavigationLink(value: MediaReference.tmdb(id: summary.id, kind: summary.kind)) {
            MediaCard(summary: summary, width: width)
        }
        .buttonStyle(.plain)
        .contextMenu {
            DiscoverQuickAddItems(summary: summary) { status in
                add(status)
            }
        }
        .sensoryFeedback(.success, trigger: addCount)
    }

    // MARK: Quick add

    /// Menu order and wording for the quick-add actions.
    static let quickAddStatuses: [WatchStatus] = [.watchlist, .watching, .watched]

    /// "Add to Watchlist" / "Start Watching" / "Mark Watched".
    static func quickAddTitle(for status: WatchStatus) -> String {
        switch status {
        case .watchlist: return "Add to Watchlist"
        case .watching: return "Start Watching"
        case .watched: return "Mark Watched"
        }
    }

    private func add(_ status: WatchStatus) {
        let store = LibraryStore(context: modelContext)
        store.add(summary, status: status)
        addCount += 1
    }
}

// MARK: - DiscoverQuickAddItems

/// The context-menu rows for a catalog result. Kept as its own view so the
/// library lookup runs only when the menu is actually presented.
private struct DiscoverQuickAddItems: View {

    let summary: MediaSummary
    let onSelect: (WatchStatus) -> Void

    @Environment(\.modelContext) private var modelContext

    init(summary: MediaSummary, onSelect: @escaping (WatchStatus) -> Void) {
        self.summary = summary
        self.onSelect = onSelect
    }

    var body: some View {
        rows(current: LibraryStore(context: modelContext).status(of: summary))
    }

    private func rows(current: WatchStatus?) -> some View {
        ForEach(DiscoverCard.quickAddStatuses) { status in
            Button {
                onSelect(status)
            } label: {
                Label(
                    DiscoverCard.quickAddTitle(for: status),
                    systemImage: current == status ? "checkmark" : status.symbolName
                )
            }
        }
    }
}

// MARK: - Preview

private func previewState(
    items: [MediaSummary] = [],
    isLoading: Bool = false,
    errorMessage: String? = nil,
    hasLoaded: Bool = false
) -> DiscoverSectionState {
    var state = DiscoverSectionState()
    state.items = items
    state.isLoading = isLoading
    state.errorMessage = errorMessage
    state.lastLoadedPage = (hasLoaded || !items.isEmpty) ? 1 : 0
    state.totalPages = 3
    return state
}

#Preview("Carousel states") {
    NavigationStack {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                MediaCarousel(
                    title: "Trending Today",
                    state: previewState(items: PreviewData.sampleSummaries),
                    onRetry: {},
                    seeAll: { Text("See All") }
                )
                MediaCarousel(title: "Airing Today", state: previewState(isLoading: true), onRetry: {})
                MediaCarousel(
                    title: "In Theaters",
                    state: previewState(errorMessage: "Your TMDB API key was rejected."),
                    onRetry: {}
                )
                MediaCarousel(title: "Coming Soon", state: previewState(hasLoaded: true), onRetry: {})
            }
            .padding(.vertical)
        }
        .navigationTitle("Discover")
    }
    .modelContainer(PreviewData.container)
}
