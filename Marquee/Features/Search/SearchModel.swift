import Foundation
import Observation
import MarqueeKit

// MARK: - SearchScope

/// The scope bar under the search field: everything, shows only or movies only.
enum SearchScope: String, CaseIterable, Identifiable, Hashable {
    case all
    case shows
    case movies

    var id: String { rawValue }

    /// Scope bar title.
    var title: String {
        switch self {
        case .all: return "All"
        case .shows: return "Shows"
        case .movies: return "Movies"
        }
    }

    /// The TMDB search kind; `nil` means multi search.
    var kind: MediaKind? {
        switch self {
        case .all: return nil
        case .shows: return .show
        case .movies: return .movie
        }
    }
}

// MARK: - SearchModel

/// Drives the Search tab: a debounced TMDB search with paging, plus the
/// "Trending This Week" grid shown while the query is empty.
///
/// Every request belongs to a generation. `search(client:)` starts a new
/// generation and cancels the previous task, so a slow, superseded request can
/// never overwrite newer results.
@MainActor
@Observable
final class SearchModel {

    /// TMDB rejects requests for pages beyond this.
    static let maximumPage = 500

    /// Delay between the last keystroke and the request.
    static let debounce: Duration = .milliseconds(300)

    // MARK: Input

    /// The search field text.
    var query: String = ""

    /// The selected scope.
    var scope: SearchScope = .all

    // MARK: Results

    /// Rows for the current query, de-duplicated by `MediaSummary.key`.
    private(set) var results: [MediaSummary] = []

    /// `true` while page 1 for the current query is pending (including the debounce delay).
    private(set) var isLoading = false

    /// `true` while a page after the first is being fetched.
    private(set) var isLoadingMore = false

    /// Failure of the most recent page 1 request, if any.
    private(set) var errorMessage: String?

    /// Failure of the most recent additional page fetch, if any.
    private(set) var pagingErrorMessage: String?

    /// `true` once a request for the current query has finished (with rows, none, or an error).
    private(set) var hasSearched = false

    // MARK: Trending

    /// Trending rows (all media, this week) for the empty-query state.
    private(set) var trending: [MediaSummary] = []

    /// `true` while trending is being (re)loaded.
    private(set) var isLoadingTrending = false

    /// Failure of the most recent trending load, if any.
    private(set) var trendingErrorMessage: String?

    /// `true` once trending loaded successfully at least once.
    private(set) var hasLoadedTrending = false

    // MARK: Private state

    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var loadMoreTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var trendingGeneration = 0
    @ObservationIgnored private var lastLoadedPage = 0
    @ObservationIgnored private var totalPages = 1
    @ObservationIgnored private var requestedText: String?
    @ObservationIgnored private var requestedKind: MediaKind?

    init() {}

    // MARK: Derived

    /// The query with surrounding whitespace removed; what is actually sent to TMDB.
    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `true` when there is something to search for.
    var isSearching: Bool {
        !trimmedQuery.isEmpty
    }

    /// `true` when another page of results can be requested.
    var canLoadMore: Bool {
        hasSearched && errorMessage == nil && !isLoading && !isLoadingMore && lastLoadedPage < totalPages
    }

    // MARK: Search

    /// Schedules a search for the current query and scope.
    ///
    /// The request starts after a short debounce, or right away when
    /// `immediate` is `true` (Return key). Any earlier pending request is
    /// cancelled. Repeating the request that is already loading or already on
    /// screen is a no-op unless `force` is `true`. An empty query clears the
    /// results so the view shows trending again.
    func search(client: TMDBClient?, immediate: Bool = false, force: Bool = false) {
        let text = trimmedQuery
        let kind = scope.kind

        guard !text.isEmpty, let client else {
            cancelRequests()
            clearResults()
            return
        }

        let sameRequest = text == requestedText && kind == requestedKind
        if sameRequest, !force {
            if isLoading, !immediate {
                return
            }
            if !isLoading, hasSearched, errorMessage == nil {
                return
            }
        }

        cancelRequests()
        let current = generation
        requestedText = text
        requestedKind = kind
        isLoading = true
        errorMessage = nil
        isLoadingMore = false
        pagingErrorMessage = nil

        searchTask = Task { [weak self] in
            if !immediate {
                do {
                    try await Task.sleep(for: SearchModel.debounce)
                } catch {
                    return
                }
            }
            guard !Task.isCancelled, let self else { return }
            await self.performSearch(text: text, kind: kind, client: client, generation: current)
        }
    }

    /// Re-runs the current search right away (Retry buttons).
    func retry(client: TMDBClient?) {
        search(client: client, immediate: true, force: true)
    }

    private func performSearch(text: String, kind: MediaKind?, client: TMDBClient, generation current: Int) async {
        do {
            let response = try await client.search(text, kind: kind, page: 1)
            guard current == generation, !Task.isCancelled else { return }
            results = SearchModel.deduplicated(response.results)
            lastLoadedPage = max(response.page, 1)
            totalPages = SearchModel.clampedPageCount(response.totalPages)
            hasSearched = true
            isLoading = false
            errorMessage = nil
        } catch {
            guard current == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            isLoading = false
            hasSearched = true
            errorMessage = SearchModel.message(for: error)
        }
    }

    // MARK: Paging

    /// Fetches the next page of results for the current query, if there is one.
    func loadMore(client: TMDBClient?) {
        guard let client, canLoadMore else { return }
        let nextPage = lastLoadedPage + 1
        guard nextPage <= SearchModel.maximumPage else { return }

        let current = generation
        let text = requestedText ?? trimmedQuery
        let kind = requestedKind
        isLoadingMore = true
        pagingErrorMessage = nil

        loadMoreTask?.cancel()
        loadMoreTask = Task { [weak self] in
            guard let self else { return }
            await self.performLoadMore(text: text, kind: kind, page: nextPage, client: client, generation: current)
        }
    }

    private func performLoadMore(text: String, kind: MediaKind?, page: Int, client: TMDBClient, generation current: Int) async {
        do {
            let response = try await client.search(text, kind: kind, page: page)
            guard current == generation, !Task.isCancelled else { return }
            append(response.results)
            lastLoadedPage = max(lastLoadedPage, page)
            totalPages = SearchModel.clampedPageCount(response.totalPages)
            isLoadingMore = false
        } catch {
            guard current == generation, !Task.isCancelled, !(error is CancellationError) else { return }
            isLoadingMore = false
            pagingErrorMessage = SearchModel.message(for: error)
        }
    }

    // MARK: Trending

    /// Loads "Trending This Week" across shows and movies. With `force == false`
    /// a successful earlier load is kept.
    func loadTrending(client: TMDBClient?, force: Bool = false) async {
        guard let client else {
            trendingGeneration += 1
            trending = []
            hasLoadedTrending = false
            isLoadingTrending = false
            trendingErrorMessage = nil
            return
        }
        if !force, hasLoadedTrending, trendingErrorMessage == nil {
            return
        }

        trendingGeneration += 1
        let current = trendingGeneration
        isLoadingTrending = true
        trendingErrorMessage = nil

        do {
            let response = try await client.trending(.all, window: .week, page: 1)
            guard current == trendingGeneration else { return }
            trending = SearchModel.deduplicated(response.results)
            hasLoadedTrending = true
            isLoadingTrending = false
        } catch {
            guard current == trendingGeneration else { return }
            isLoadingTrending = false
            if Task.isCancelled || error is CancellationError { return }
            trendingErrorMessage = SearchModel.message(for: error)
        }
    }

    // MARK: Reset

    /// Forgets results and trending rows (used when the TMDB credential goes away).
    func reset() {
        cancelRequests()
        clearResults()
        trendingGeneration += 1
        trending = []
        hasLoadedTrending = false
        isLoadingTrending = false
        trendingErrorMessage = nil
    }

    // MARK: Private helpers

    private func cancelRequests() {
        searchTask?.cancel()
        searchTask = nil
        loadMoreTask?.cancel()
        loadMoreTask = nil
        generation += 1
    }

    private func clearResults() {
        results = []
        isLoading = false
        isLoadingMore = false
        errorMessage = nil
        pagingErrorMessage = nil
        hasSearched = false
        lastLoadedPage = 0
        totalPages = 1
        requestedText = nil
        requestedKind = nil
    }

    private func append(_ newItems: [MediaSummary]) {
        var seen = Set(results.map { $0.key })
        for item in newItems where seen.insert(item.key).inserted {
            results.append(item)
        }
    }

    /// `items` with later duplicates (same `key`) removed.
    static func deduplicated(_ items: [MediaSummary]) -> [MediaSummary] {
        var seen = Set<String>()
        return items.filter { seen.insert($0.key).inserted }
    }

    private static func clampedPageCount(_ total: Int) -> Int {
        min(max(total, 1), maximumPage)
    }

    /// Human-readable text for a failed request.
    static func message(for error: Error) -> String {
        if let tmdbError = error as? TMDBError, let description = tmdbError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
