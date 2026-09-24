import Foundation
import Observation
import MarqueeKit

// MARK: - DiscoverSectionKind

/// The carousels on the Discover tab, in display order.
enum DiscoverSectionKind: String, CaseIterable, Identifiable, Hashable {
    case trendingToday
    case airingToday
    case onTheAir
    case inTheaters
    case comingSoon
    case popularShows
    case popularMovies

    var id: String { rawValue }

    /// Header text, also used as the See All screen's title.
    var title: String {
        switch self {
        case .trendingToday: return "Trending Today"
        case .airingToday: return "Airing Today"
        case .onTheAir: return "On the Air This Week"
        case .inTheaters: return "In Theaters"
        case .comingSoon: return "Coming Soon"
        case .popularShows: return "Popular Shows"
        case .popularMovies: return "Popular Movies"
        }
    }

    /// SF Symbol used by the section's empty state.
    var symbolName: String {
        switch self {
        case .trendingToday: return "flame"
        case .airingToday, .onTheAir, .popularShows: return "tv"
        case .inTheaters, .comingSoon, .popularMovies: return "film"
        }
    }

    /// Explanation shown when TMDB returns no rows for the section.
    var emptyDescription: String {
        switch self {
        case .trendingToday: return "Nothing is trending right now."
        case .airingToday: return "No shows are airing today."
        case .onTheAir: return "No shows are airing this week."
        case .inTheaters: return "No movies are playing in your region right now."
        case .comingSoon: return "No upcoming movies are listed for your region."
        case .popularShows: return "No popular shows to show right now."
        case .popularMovies: return "No popular movies to show right now."
        }
    }

    /// Fetches one page of a section from a `TMDBClient`.
    typealias Loader = (TMDBClient, Int) async throws -> PagedResponse<MediaSummary>

    /// The client call backing this section.
    var loader: Loader {
        switch self {
        case .trendingToday:
            return { client, page in try await client.trending(.all, window: .day, page: page) }
        case .airingToday:
            return { client, page in try await client.airingToday(page: page) }
        case .onTheAir:
            return { client, page in try await client.onTheAir(page: page) }
        case .inTheaters:
            return { client, page in try await client.nowPlayingMovies(page: page) }
        case .comingSoon:
            return { client, page in try await client.upcomingMovies(page: page) }
        case .popularShows:
            return { client, page in try await client.popularShows(page: page) }
        case .popularMovies:
            return { client, page in try await client.popularMovies(page: page) }
        }
    }
}

// MARK: - DiscoverSectionState

/// Everything a carousel or See All grid needs to render one section.
struct DiscoverSectionState: Equatable {

    /// Rows loaded so far, de-duplicated by `MediaSummary.key`.
    var items: [MediaSummary] = []
    /// `true` while page 1 is being (re)loaded.
    var isLoading: Bool = false
    /// Failure of the most recent page 1 load, if any.
    var errorMessage: String?

    /// Highest TMDB page merged into `items`; 0 until the first load succeeds.
    var lastLoadedPage: Int = 0
    /// Total pages TMDB reported (clamped to what it will actually serve).
    var totalPages: Int = 1
    /// `true` while a page after the first is being fetched.
    var isLoadingMore: Bool = false
    /// Failure of the most recent additional page fetch, if any.
    var pagingErrorMessage: String?

    // MARK: Derived

    /// `true` once page 1 has loaded successfully at least once.
    var hasLoaded: Bool { lastLoadedPage > 0 }

    /// `true` when another page can be requested.
    var canLoadMore: Bool { hasLoaded && lastLoadedPage < totalPages }

    /// `true` when nothing is available to show yet and a redacted placeholder is appropriate:
    /// either a load is in flight or no load has happened yet.
    var showsPlaceholder: Bool {
        guard items.isEmpty else { return false }
        if isLoading { return true }
        return !hasLoaded && errorMessage == nil
    }

    // MARK: Mutation

    /// Appends rows whose `key` is not already present.
    mutating func append(_ newItems: [MediaSummary]) {
        var seen = Set(items.map { $0.key })
        for item in newItems where seen.insert(item.key).inserted {
            items.append(item)
        }
    }

    /// `items` with later duplicates (same `key`) removed.
    static func deduplicated(_ items: [MediaSummary]) -> [MediaSummary] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.key).inserted }
    }
}

// MARK: - DiscoverModel

/// Loads and pages the Discover sections. Owned with `@State` by `DiscoverView`
/// (all sections) and by `SeeAllView` (one section, seeded from the carousel).
///
/// Every request carries a per-section token so that a superseded request
/// (pull to refresh during an initial load, or a `.task` restarted after a
/// cancellation) can never overwrite newer results.
@MainActor
@Observable
final class DiscoverModel {

    /// TMDB rejects requests for pages beyond this.
    static let maximumPage = 500

    /// State per section. Every `DiscoverSectionKind` always has an entry.
    private(set) var sections: [DiscoverSectionKind: DiscoverSectionState] = DiscoverModel.emptySections()

    /// The region the sections were last loaded for. `DiscoverView` compares it
    /// with `AppSettings.region` to force a reload after the user changes region.
    @ObservationIgnored var loadedRegion: String?

    /// Token of the most recent page 1 request per section.
    @ObservationIgnored private var requestTokens: [DiscoverSectionKind: UUID] = [:]

    init() {}

    // MARK: Reading

    /// The current state of `section`.
    func state(for section: DiscoverSectionKind) -> DiscoverSectionState {
        sections[section] ?? DiscoverSectionState()
    }

    /// `true` when every section failed and none has anything to show.
    var allSectionsFailed: Bool {
        DiscoverSectionKind.allCases.allSatisfy { kind in
            let state = self.state(for: kind)
            return state.items.isEmpty && !state.isLoading && state.errorMessage != nil
        }
    }

    /// The first section error, for a combined failure screen.
    var firstErrorMessage: String? {
        DiscoverSectionKind.allCases.compactMap { self.state(for: $0).errorMessage }.first
    }

    // MARK: Seeding and reset

    /// Starts `section` from a state loaded elsewhere (the carousel hands its
    /// rows to the See All grid so paging continues from the next page).
    func seed(section: DiscoverSectionKind, with state: DiscoverSectionState) {
        var seeded = state
        seeded.isLoading = false
        seeded.isLoadingMore = false
        seeded.pagingErrorMessage = nil
        sections[section] = seeded
    }

    /// Forgets everything, including in-flight requests. Used when the TMDB
    /// credential is removed so the next credential starts clean.
    func reset() {
        requestTokens.removeAll()
        loadedRegion = nil
        sections = DiscoverModel.emptySections()
    }

    // MARK: Loading

    /// Loads every section concurrently. With `force == false` sections that
    /// already loaded successfully are left alone.
    func loadAll(client: TMDBClient, force: Bool) async {
        await withTaskGroup(of: Void.self) { group in
            for section in DiscoverSectionKind.allCases {
                group.addTask {
                    await self.load(section: section, client: client, force: force)
                }
            }
        }
    }

    /// Loads (or reloads) page 1 of `section`. Existing rows stay visible until
    /// the new page arrives; a cancelled request leaves no error behind.
    func load(section: DiscoverSectionKind, client: TMDBClient, force: Bool = false) async {
        let current = state(for: section)
        if !force, current.hasLoaded, current.errorMessage == nil {
            return
        }

        let token = UUID()
        requestTokens[section] = token
        update(section) { state in
            state.isLoading = true
            state.errorMessage = nil
            state.isLoadingMore = false
            state.pagingErrorMessage = nil
        }

        do {
            let response = try await section.loader(client, 1)
            guard requestTokens[section] == token else { return }
            update(section) { state in
                state.items = DiscoverSectionState.deduplicated(response.results)
                state.lastLoadedPage = max(response.page, 1)
                state.totalPages = DiscoverModel.clampedPageCount(response.totalPages)
                state.isLoading = false
                state.errorMessage = nil
            }
        } catch {
            guard requestTokens[section] == token else { return }
            let wasCancelled = Task.isCancelled || error is CancellationError
            update(section) { state in
                state.isLoading = false
                if !wasCancelled {
                    state.errorMessage = DiscoverModel.message(for: error)
                }
            }
        }
    }

    // MARK: Paging

    /// Fetches the page after the last one merged into `section`, if any.
    func loadMore(section: DiscoverSectionKind, client: TMDBClient) async {
        let current = state(for: section)
        guard current.canLoadMore, !current.isLoading, !current.isLoadingMore else { return }
        await page(for: section, page: current.lastLoadedPage + 1, client: client)
    }

    /// Fetches a specific page of `section` and merges it. Page 1 is a full
    /// reload; later pages append. A page 1 reload that starts while a later
    /// page is in flight wins: the late page is discarded.
    func page(for section: DiscoverSectionKind, page number: Int, client: TMDBClient) async {
        guard number > 1 else {
            await load(section: section, client: client, force: true)
            return
        }
        guard number <= DiscoverModel.maximumPage else { return }

        let token = requestTokens[section]
        update(section) { state in
            state.isLoadingMore = true
            state.pagingErrorMessage = nil
        }

        do {
            let response = try await section.loader(client, number)
            guard requestTokens[section] == token else { return }
            update(section) { state in
                state.append(response.results)
                state.lastLoadedPage = max(state.lastLoadedPage, number)
                state.totalPages = DiscoverModel.clampedPageCount(response.totalPages)
                state.isLoadingMore = false
            }
        } catch {
            guard requestTokens[section] == token else { return }
            let wasCancelled = Task.isCancelled || error is CancellationError
            update(section) { state in
                state.isLoadingMore = false
                if !wasCancelled {
                    state.pagingErrorMessage = DiscoverModel.message(for: error)
                }
            }
        }
    }

    // MARK: Private helpers

    private func update(_ section: DiscoverSectionKind, _ change: (inout DiscoverSectionState) -> Void) {
        var state = sections[section] ?? DiscoverSectionState()
        change(&state)
        sections[section] = state
    }

    private static func emptySections() -> [DiscoverSectionKind: DiscoverSectionState] {
        var sections: [DiscoverSectionKind: DiscoverSectionState] = [:]
        for kind in DiscoverSectionKind.allCases {
            sections[kind] = DiscoverSectionState()
        }
        return sections
    }

    private static func clampedPageCount(_ total: Int) -> Int {
        min(max(total, 1), maximumPage)
    }

    /// Human-readable text for a failed request.
    private static func message(for error: Error) -> String {
        if let tmdbError = error as? TMDBError, let description = tmdbError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
