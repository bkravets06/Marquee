import XCTest
import MarqueeKit
@testable import Marquee

// MARK: - DiscoverModelTests

/// Pure, network-free coverage of `DiscoverSectionState` and the parts of
/// `DiscoverModel` that do not touch a `TMDBClient` (seeding, reset, failure
/// roll-up).
@MainActor
final class DiscoverModelTests: XCTestCase {

    // MARK: Helpers

    private func summary(id: Int, kind: MediaKind) -> MediaSummary {
        MediaSummary(
            id: id,
            kind: kind,
            title: "Title \(id)",
            overview: "",
            posterPath: nil,
            backdropPath: nil,
            releaseDate: nil,
            voteAverage: 0,
            voteCount: 0,
            popularity: 0,
            genreIDs: [],
            originalLanguage: nil
        )
    }

    private func failedState(_ message: String) -> DiscoverSectionState {
        var state = DiscoverSectionState()
        state.errorMessage = message
        return state
    }

    private func loadedState(_ items: [MediaSummary]) -> DiscoverSectionState {
        var state = DiscoverSectionState()
        state.items = items
        state.lastLoadedPage = 1
        return state
    }

    // MARK: DiscoverSectionState

    func testDeduplicatedKeepsFirstOccurrenceAndDistinguishesKinds() {
        let items = [
            summary(id: 1, kind: .show),
            summary(id: 2, kind: .show),
            summary(id: 1, kind: .movie),
            summary(id: 1, kind: .show),
            summary(id: 2, kind: .show)
        ]
        let result = DiscoverSectionState.deduplicated(items)
        XCTAssertEqual(result.map { $0.key }, ["show-1", "show-2", "movie-1"])
        XCTAssertEqual(result.first?.title, "Title 1")
    }

    func testAppendSkipsExistingAndInBatchDuplicatesPreservingOrder() {
        var state = DiscoverSectionState()
        state.items = [summary(id: 1, kind: .show), summary(id: 2, kind: .movie)]

        state.append([
            summary(id: 2, kind: .movie),
            summary(id: 3, kind: .show),
            summary(id: 3, kind: .show),
            summary(id: 1, kind: .movie),
            summary(id: 1, kind: .show)
        ])

        XCTAssertEqual(state.items.map { $0.key }, ["show-1", "movie-2", "show-3", "movie-1"])
    }

    func testShowsPlaceholder() {
        XCTAssertTrue(DiscoverSectionState().showsPlaceholder)

        var loading = DiscoverSectionState()
        loading.isLoading = true
        XCTAssertTrue(loading.showsPlaceholder)

        var loadedEmpty = DiscoverSectionState()
        loadedEmpty.lastLoadedPage = 1
        XCTAssertFalse(loadedEmpty.isLoading)
        XCTAssertFalse(loadedEmpty.showsPlaceholder)

        var failed = DiscoverSectionState()
        failed.errorMessage = "Your TMDB API key was rejected."
        XCTAssertEqual(failed.lastLoadedPage, 0)
        XCTAssertFalse(failed.showsPlaceholder)

        var withItems = DiscoverSectionState()
        withItems.items = [summary(id: 1, kind: .show)]
        XCTAssertFalse(withItems.showsPlaceholder)
        withItems.isLoading = true
        XCTAssertFalse(withItems.showsPlaceholder)
    }

    func testHasLoadedAndCanLoadMore() {
        var state = DiscoverSectionState()
        XCTAssertEqual(state.lastLoadedPage, 0)
        XCTAssertFalse(state.hasLoaded)
        XCTAssertFalse(state.canLoadMore)

        state.lastLoadedPage = 1
        state.totalPages = 3
        XCTAssertTrue(state.hasLoaded)
        XCTAssertTrue(state.canLoadMore)

        state.lastLoadedPage = 3
        XCTAssertTrue(state.hasLoaded)
        XCTAssertFalse(state.canLoadMore)
    }

    // MARK: DiscoverModel

    func testSeedKeepsRowsAndPagingButClearsTransientFlags() {
        let model = DiscoverModel()
        var seeded = DiscoverSectionState()
        seeded.items = [summary(id: 1, kind: .show)]
        seeded.lastLoadedPage = 2
        seeded.totalPages = 5
        seeded.errorMessage = "Stale error"
        seeded.isLoading = true
        seeded.isLoadingMore = true
        seeded.pagingErrorMessage = "Paging failed"

        model.seed(section: .popularShows, with: seeded)

        let state = model.state(for: .popularShows)
        XCTAssertEqual(state.items.map { $0.key }, ["show-1"])
        XCTAssertEqual(state.lastLoadedPage, 2)
        XCTAssertEqual(state.totalPages, 5)
        XCTAssertEqual(state.errorMessage, "Stale error")
        XCTAssertFalse(state.isLoading)
        XCTAssertFalse(state.isLoadingMore)
        XCTAssertNil(state.pagingErrorMessage)
        XCTAssertEqual(model.state(for: .trendingToday), DiscoverSectionState())
    }

    func testResetClearsEverySectionAndRegion() {
        let model = DiscoverModel()
        model.loadedRegion = "US"
        for section in DiscoverSectionKind.allCases {
            model.seed(section: section, with: loadedState([summary(id: 1, kind: .movie)]))
        }
        XCTAssertNotEqual(model.state(for: .comingSoon), DiscoverSectionState())

        model.reset()

        XCTAssertNil(model.loadedRegion)
        for section in DiscoverSectionKind.allCases {
            XCTAssertEqual(model.state(for: section), DiscoverSectionState(), "\(section.rawValue)")
        }
    }

    func testAllSectionsFailedAndFirstErrorMessage() {
        let model = DiscoverModel()
        XCTAssertFalse(model.allSectionsFailed)
        XCTAssertNil(model.firstErrorMessage)

        for section in DiscoverSectionKind.allCases {
            model.seed(section: section, with: failedState("\(section.rawValue) failed"))
        }
        XCTAssertTrue(model.allSectionsFailed)
        XCTAssertEqual(model.firstErrorMessage, "trendingToday failed")

        model.seed(section: .popularMovies, with: loadedState([summary(id: 7, kind: .show)]))
        XCTAssertFalse(model.allSectionsFailed)
        XCTAssertEqual(model.firstErrorMessage, "trendingToday failed")
    }

    func testOneSuccessfulSectionMeansNotAllFailed() {
        let model = DiscoverModel()
        for section in DiscoverSectionKind.allCases where section != .trendingToday {
            model.seed(section: section, with: failedState("Down"))
        }
        model.seed(section: .trendingToday, with: loadedState([summary(id: 1, kind: .show)]))
        XCTAssertFalse(model.allSectionsFailed)
        XCTAssertEqual(model.firstErrorMessage, "Down")
    }
}
