import XCTest
import SwiftData
import MarqueeKit
@testable import Marquee

// MARK: - LibraryStoreTests

@MainActor
final class LibraryStoreTests: XCTestCase {

    /// Keeps the current test's container alive for the duration of the test.
    private var container: ModelContainer?

    private static let twoSeasons: [SeasonInfo] = [
        SeasonInfo(number: 1, name: "Season 1", episodeCount: 2),
        SeasonInfo(number: 2, name: "Season 2", episodeCount: 3)
    ]

    // MARK: Helpers

    private func makeStore() throws -> LibraryStore {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MediaItem.self, configurations: configuration)
        self.container = container
        return LibraryStore(context: container.mainContext)
    }

    /// Inserts a TMDB show. `seasons` defaults to `twoSeasons` when `nil`
    /// (resolved inside the body so the default argument stays isolation-free).
    @discardableResult
    private func makeShow(
        in store: LibraryStore,
        status: WatchStatus,
        tmdbID: Int = 1,
        title: String = "Test Show",
        seasons: [SeasonInfo]? = nil
    ) -> MediaItem {
        let item = MediaItem(kind: .show, status: status, title: title, tmdbID: tmdbID)
        item.seasons = seasons ?? LibraryStoreTests.twoSeasons
        store.context.insert(item)
        store.save()
        return item
    }

    // MARK: Adding

    func testAddIsIdempotentAndUpdatesStatus() throws {
        let store = try makeStore()

        let first = store.add(PreviewData.sampleSummary, status: .watchlist)
        XCTAssertEqual(first.status, .watchlist)
        XCTAssertEqual(first.tmdbID, PreviewData.sampleSummary.id)
        XCTAssertEqual(first.kind, .show)
        XCTAssertEqual(first.title, "Severance")

        let second = store.add(PreviewData.sampleSummary, status: .watching)
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(store.allItems().count, 1)
        XCTAssertEqual(first.status, .watching)

        XCTAssertEqual(store.status(of: PreviewData.sampleSummary), .watching)
        XCTAssertNil(store.status(of: PreviewData.sampleMovieSummary))
        XCTAssertEqual(store.items(status: .watching).count, 1)
        XCTAssertEqual(store.items(status: .watchlist).count, 0)
    }

    func testAddAsWatchedSetsFinishedAt() throws {
        let store = try makeStore()
        let item = store.add(PreviewData.sampleMovieSummary, status: .watched)
        XCTAssertEqual(item.status, .watched)
        XCTAssertNotNil(item.finishedAt)
        XCTAssertNotNil(item.lastWatchedAt)
    }

    func testReminderDefaults() throws {
        let store = try makeStore()

        let watchingShow = store.add(PreviewData.sampleSummary, status: .watching)
        XCTAssertTrue(watchingShow.notificationsEnabled)

        let movie = store.add(PreviewData.sampleMovieSummary, status: .watching)
        XCTAssertFalse(movie.notificationsEnabled)

        let listed = makeShow(in: store, status: .watchlist, tmdbID: 2, title: "Listed")
        XCTAssertFalse(listed.notificationsEnabled)
        store.setStatus(listed, to: .watching)
        XCTAssertTrue(listed.notificationsEnabled)

        let promoted = makeShow(in: store, status: .watchlist, tmdbID: 3, title: "Promoted")
        store.setProgress(promoted, to: EpisodePointer(season: 1, episode: 1))
        XCTAssertEqual(promoted.status, .watching)
        XCTAssertTrue(promoted.notificationsEnabled)

        let finished = makeShow(in: store, status: .watched, tmdbID: 4, title: "Finished")
        store.setStatus(finished, to: .watching)
        XCTAssertFalse(finished.notificationsEnabled)

        let custom = store.addCustom(title: "Custom", kind: .show, status: .watchlist, overview: "", posterData: nil, linkURL: nil, notes: "", totalEpisodes: nil, schedule: nil, notificationsEnabled: false)
        store.setStatus(custom, to: .watching)
        XCTAssertFalse(custom.notificationsEnabled)
    }

    func testAddCustomPersistsScheduleAndPoster() throws {
        let store = try makeStore()
        let schedule = ReleaseSchedule(weekday: 3, hour: 20, minute: 0)
        let poster = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
        let link = URL(string: "https://example.com/show")

        let created = store.addCustom(
            title: "My Custom Show",
            kind: .show,
            status: .watching,
            overview: "A show I track by hand.",
            posterData: poster,
            linkURL: link,
            notes: "Tuesdays with friends",
            totalEpisodes: 10,
            schedule: schedule,
            notificationsEnabled: true
        )

        let fetched = try XCTUnwrap(store.item(id: created.id))
        XCTAssertTrue(fetched.isCustom)
        XCTAssertNil(fetched.tmdbID)
        XCTAssertEqual(fetched.kind, .show)
        XCTAssertEqual(fetched.status, .watching)
        XCTAssertEqual(fetched.overview, "A show I track by hand.")
        XCTAssertEqual(fetched.customPosterData, poster)
        XCTAssertEqual(fetched.linkURL, link)
        XCTAssertEqual(fetched.notes, "Tuesdays with friends")
        XCTAssertEqual(fetched.totalEpisodes, 10)
        XCTAssertEqual(fetched.releaseSchedule, schedule)
        XCTAssertNotNil(fetched.releaseScheduleData)
        XCTAssertTrue(fetched.notificationsEnabled)
        XCTAssertEqual(fetched.nextUp, EpisodePointer(season: 1, episode: 1))
    }

    func testAddCustomMovieIgnoresShowOnlyFields() throws {
        let store = try makeStore()
        let created = store.addCustom(
            title: "Home Movie",
            kind: .movie,
            status: .watchlist,
            overview: "",
            posterData: nil,
            linkURL: nil,
            notes: "",
            totalEpisodes: 5,
            schedule: ReleaseSchedule(weekday: 1, hour: 9, minute: 0),
            notificationsEnabled: true
        )
        XCTAssertTrue(created.isMovie)
        XCTAssertNil(created.totalEpisodes)
        XCTAssertNil(created.releaseSchedule)
        XCTAssertFalse(created.notificationsEnabled)
        XCTAssertNil(created.nextUp)
    }

    func testUpdateCustomRewritesFieldsAndClearsShowFieldsForMovies() throws {
        let store = try makeStore()
        let item = store.addCustom(
            title: "Old",
            kind: .show,
            status: .watching,
            overview: "",
            posterData: nil,
            linkURL: nil,
            notes: "",
            totalEpisodes: 8,
            schedule: ReleaseSchedule(weekday: 2, hour: 20, minute: 0),
            notificationsEnabled: true
        )
        store.setProgress(item, to: EpisodePointer(season: 1, episode: 3))
        let before = item.updatedAt

        store.updateCustom(
            item,
            title: "New",
            kind: .movie,
            overview: "Changed",
            posterData: nil,
            linkURL: URL(string: "https://example.com"),
            notes: "Note",
            totalEpisodes: 8,
            schedule: ReleaseSchedule(weekday: 2, hour: 20, minute: 0),
            notificationsEnabled: true
        )
        XCTAssertEqual(item.title, "New")
        XCTAssertTrue(item.isMovie)
        XCTAssertEqual(item.overview, "Changed")
        XCTAssertEqual(item.notes, "Note")
        XCTAssertEqual(item.linkURL?.absoluteString, "https://example.com")
        XCTAssertNil(item.totalEpisodes)
        XCTAssertNil(item.releaseSchedule)
        XCTAssertFalse(item.notificationsEnabled)
        XCTAssertEqual(item.progress, .notStarted)
        XCTAssertEqual(item.status, .watching)
        XCTAssertGreaterThanOrEqual(item.updatedAt, before)
    }

    // MARK: Status

    func testSetStatusWatchedSetsFinishedAt() throws {
        let store = try makeStore()
        let item = store.add(PreviewData.sampleMovieSummary, status: .watchlist)
        XCTAssertNil(item.finishedAt)
        XCTAssertNil(item.lastWatchedAt)

        let before = item.updatedAt
        store.setStatus(item, to: .watched)
        XCTAssertEqual(item.status, .watched)
        XCTAssertNotNil(item.finishedAt)
        XCTAssertNotNil(item.lastWatchedAt)
        XCTAssertGreaterThanOrEqual(item.updatedAt, before)

        store.setStatus(item, to: .watching)
        XCTAssertEqual(item.status, .watching)
        XCTAssertNil(item.finishedAt)
    }

    func testMarkMovieWatched() throws {
        let store = try makeStore()
        let item = store.add(PreviewData.sampleMovieSummary, status: .watching)
        store.markMovieWatched(item)
        XCTAssertEqual(item.status, .watched)
        XCTAssertNotNil(item.finishedAt)
    }

    // MARK: Progress

    func testSetProgressPromotesWatchlistToWatching() throws {
        let store = try makeStore()
        let item = makeShow(in: store, status: .watchlist)

        store.setProgress(item, to: EpisodePointer(season: 1, episode: 2))
        XCTAssertEqual(item.status, .watching)
        XCTAssertEqual(item.progress, EpisodePointer(season: 1, episode: 2))
        XCTAssertNotNil(item.lastWatchedAt)
    }

    func testSetProgressKeepsWatchedStatus() throws {
        let store = try makeStore()
        let item = makeShow(in: store, status: .watched)
        store.setProgress(item, to: EpisodePointer(season: 2, episode: 3))
        XCTAssertEqual(item.status, .watched)
    }

    func testMarkNextEpisodeWatchedFromNotStarted() throws {
        let store = try makeStore()
        let item = makeShow(in: store, status: .watching)
        XCTAssertEqual(item.progress, .notStarted)
        XCTAssertEqual(item.nextUp, EpisodePointer(season: 1, episode: 1))

        store.markNextEpisodeWatched(item)
        XCTAssertEqual(item.progress, EpisodePointer(season: 1, episode: 1))
        XCTAssertEqual(item.watchedEpisodeCount, 1)
    }

    func testMarkNextEpisodeWatchedRollsOverSeason() throws {
        let store = try makeStore()
        let item = makeShow(in: store, status: .watching)
        store.setProgress(item, to: EpisodePointer(season: 1, episode: 2))

        store.markNextEpisodeWatched(item)
        XCTAssertEqual(item.progress, EpisodePointer(season: 2, episode: 1))
        XCTAssertEqual(item.watchedEpisodeCount, 3)
    }

    func testMarkNextEpisodeWatchedIsNoOpWhenCaughtUp() throws {
        let store = try makeStore()
        let item = makeShow(in: store, status: .watching)
        store.setProgress(item, to: EpisodePointer(season: 2, episode: 3))
        XCTAssertNil(item.nextUp)

        let updated = item.updatedAt
        store.markNextEpisodeWatched(item)
        XCTAssertEqual(item.progress, EpisodePointer(season: 2, episode: 3))
        XCTAssertEqual(item.updatedAt, updated)
        XCTAssertEqual(item.status, .watching)
    }

    func testMarkNextEpisodeWatchedIgnoresMovies() throws {
        let store = try makeStore()
        let movie = store.add(PreviewData.sampleMovieSummary, status: .watching)
        store.markNextEpisodeWatched(movie)
        XCTAssertEqual(movie.progress, .notStarted)
    }

    func testMarkPreviousEpisodeUnwatched() throws {
        let store = try makeStore()
        let item = makeShow(in: store, status: .watching)
        store.setProgress(item, to: EpisodePointer(season: 2, episode: 1))

        store.markPreviousEpisodeUnwatched(item)
        XCTAssertEqual(item.progress, EpisodePointer(season: 1, episode: 2))

        store.markPreviousEpisodeUnwatched(item)
        XCTAssertEqual(item.progress, EpisodePointer(season: 1, episode: 1))

        store.markPreviousEpisodeUnwatched(item)
        XCTAssertEqual(item.progress, .notStarted)

        store.markPreviousEpisodeUnwatched(item)
        XCTAssertEqual(item.progress, .notStarted)
    }

    func testMarkPreviousEpisodeUnwatchedOnCustomShow() throws {
        let store = try makeStore()
        let item = store.addCustom(
            title: "Custom",
            kind: .show,
            status: .watching,
            overview: "",
            posterData: nil,
            linkURL: nil,
            notes: "",
            totalEpisodes: nil,
            schedule: nil,
            notificationsEnabled: false
        )
        store.setProgress(item, to: EpisodePointer(season: 1, episode: 2))
        store.markPreviousEpisodeUnwatched(item)
        XCTAssertEqual(item.progress, EpisodePointer(season: 1, episode: 1))
        store.markPreviousEpisodeUnwatched(item)
        XCTAssertEqual(item.progress, .notStarted)
    }

    func testSetNotifications() throws {
        let store = try makeStore()
        let item = makeShow(in: store, status: .watching)
        XCTAssertFalse(item.notificationsEnabled)
        store.setNotifications(item, enabled: true)
        XCTAssertTrue(item.notificationsEnabled)
        XCTAssertEqual(store.showsWithNotificationsEnabled().count, 1)
        store.setNotifications(item, enabled: false)
        XCTAssertEqual(store.showsWithNotificationsEnabled().count, 0)
    }

    // MARK: Refresh

    func testShowsNeedingRefresh() throws {
        let store = try makeStore()
        let now = Date.now

        let fresh = makeShow(in: store, status: .watching, tmdbID: 1, title: "Fresh")
        fresh.lastRefreshedAt = now.addingTimeInterval(-3_600)

        let stale = makeShow(in: store, status: .watchlist, tmdbID: 2, title: "Stale")
        stale.lastRefreshedAt = now.addingTimeInterval(-7 * 3_600)

        let never = makeShow(in: store, status: .watching, tmdbID: 3, title: "Never")
        XCTAssertNil(never.lastRefreshedAt)

        let watchedQuiet = makeShow(in: store, status: .watched, tmdbID: 4, title: "Watched Quiet")

        let watchedNotify = makeShow(in: store, status: .watched, tmdbID: 5, title: "Watched Notify")
        watchedNotify.notificationsEnabled = true

        let custom = store.addCustom(
            title: "Custom",
            kind: .show,
            status: .watching,
            overview: "",
            posterData: nil,
            linkURL: nil,
            notes: "",
            totalEpisodes: nil,
            schedule: nil,
            notificationsEnabled: true
        )
        let movie = store.add(PreviewData.sampleMovieSummary, status: .watching)
        store.save()

        let regular = Set(store.showsNeedingRefresh(olderThan: 6 * 3_600, now: now).map { $0.id })
        XCTAssertTrue(regular.contains(stale.id))
        XCTAssertTrue(regular.contains(never.id))
        XCTAssertTrue(regular.contains(watchedNotify.id))
        XCTAssertFalse(regular.contains(fresh.id))
        XCTAssertFalse(regular.contains(watchedQuiet.id))
        XCTAssertFalse(regular.contains(custom.id))
        XCTAssertFalse(regular.contains(movie.id))

        let forced = Set(store.showsNeedingRefresh(olderThan: 0, now: now).map { $0.id })
        XCTAssertTrue(forced.contains(fresh.id))
        XCTAssertTrue(forced.contains(stale.id))
        XCTAssertTrue(forced.contains(never.id))
        XCTAssertTrue(forced.contains(watchedNotify.id))
        XCTAssertFalse(forced.contains(watchedQuiet.id))
        XCTAssertFalse(forced.contains(custom.id))
        XCTAssertFalse(forced.contains(movie.id))
    }

    func testShowsWithNotificationsEnabledIncludesCustomShows() throws {
        let store = try makeStore()
        makeShow(in: store, status: .watching, tmdbID: 1)
        let notifying = makeShow(in: store, status: .watching, tmdbID: 2)
        notifying.notificationsEnabled = true
        let custom = store.addCustom(
            title: "Custom",
            kind: .show,
            status: .watching,
            overview: "",
            posterData: nil,
            linkURL: nil,
            notes: "",
            totalEpisodes: nil,
            schedule: ReleaseSchedule(weekday: 2, hour: 21, minute: 30),
            notificationsEnabled: true
        )
        store.save()

        let ids = Set(store.showsWithNotificationsEnabled().map { $0.id })
        XCTAssertEqual(ids, Set([notifying.id, custom.id]))
    }

    // MARK: Applying details

    func testApplyShowDetails() throws {
        let store = try makeStore()
        let item = store.add(PreviewData.sampleSummary, status: .watching)
        XCTAssertTrue(item.seasons.isEmpty)
        XCTAssertNil(item.lastRefreshedAt)

        store.apply(PreviewData.sampleShowDetails, to: item)

        XCTAssertEqual(item.title, "Severance")
        XCTAssertEqual(item.tagline, "Who are you at work?")
        XCTAssertEqual(item.genres, ["Drama", "Mystery", "Sci-Fi & Fantasy"])
        XCTAssertEqual(item.runtimeMinutes, 50)
        XCTAssertEqual(item.showStatus, "Returning Series")
        XCTAssertEqual(item.seasons.count, 2)
        XCTAssertEqual(item.seasons.map { $0.number }, [1, 2])
        XCTAssertEqual(item.totalEpisodes, 19)
        XCTAssertEqual(item.episodeTotal, 19)
        XCTAssertEqual(item.nextEpisodeSeason, 2)
        XCTAssertEqual(item.nextEpisodeNumber, 5)
        XCTAssertEqual(item.nextEpisodeName, "Trojan's Horse")
        XCTAssertNotNil(item.nextEpisodeAirDate)
        XCTAssertNotNil(item.releaseDate)
        XCTAssertNotNil(item.lastRefreshedAt)
        XCTAssertTrue(item.airsWithinDays(7))
        XCTAssertNotNil(item.nextEpisodeLabel)
    }

    func testApplyShowDetailsClearsNextEpisodeWhenAbsent() throws {
        let store = try makeStore()
        let item = store.add(PreviewData.sampleSummary, status: .watching)
        store.apply(PreviewData.sampleShowDetails, to: item)
        XCTAssertNotNil(item.nextEpisodeAirDate)

        var ended = PreviewData.sampleShowDetails
        ended.nextEpisodeToAir = nil
        ended.status = "Ended"
        store.apply(ended, to: item)

        XCTAssertNil(item.nextEpisodeAirDate)
        XCTAssertNil(item.nextEpisodeSeason)
        XCTAssertNil(item.nextEpisodeNumber)
        XCTAssertNil(item.nextEpisodeName)
        XCTAssertEqual(item.showStatus, "Ended")
        XCTAssertFalse(item.airsWithinDays(7))
    }

    func testApplyMovieDetails() throws {
        let store = try makeStore()
        let item = store.add(PreviewData.sampleMovieSummary, status: .watchlist)
        store.apply(PreviewData.sampleMovieDetails, to: item)

        XCTAssertEqual(item.title, "Dune: Part Two")
        XCTAssertEqual(item.runtimeMinutes, 167)
        XCTAssertEqual(item.genres, ["Science Fiction", "Adventure"])
        XCTAssertEqual(item.year, 2024)
        XCTAssertNotNil(item.lastRefreshedAt)
        XCTAssertEqual(item.status, .watchlist)
    }

    // MARK: Deleting

    func testDeleteAndDeleteAll() throws {
        let store = try makeStore()
        let show = store.add(PreviewData.sampleSummary, status: .watching)
        let movie = store.add(PreviewData.sampleMovieSummary, status: .watchlist)
        makeShow(in: store, status: .watched, tmdbID: 99)
        XCTAssertEqual(store.allItems().count, 3)

        store.delete(show)
        XCTAssertEqual(store.allItems().count, 2)
        XCTAssertNil(store.item(id: show.id))
        XCTAssertNotNil(store.item(id: movie.id))

        store.deleteAll()
        XCTAssertTrue(store.allItems().isEmpty)
        XCTAssertNil(store.item(id: movie.id))
        XCTAssertNil(store.item(tmdbID: PreviewData.sampleMovieSummary.id, kind: .movie))
    }

    func testLookupByTMDBIDDistinguishesKinds() throws {
        let store = try makeStore()
        let show = makeShow(in: store, status: .watching, tmdbID: 42, title: "Show 42")
        let movie = MediaItem(kind: .movie, status: .watching, title: "Movie 42", tmdbID: 42)
        store.context.insert(movie)
        store.save()

        XCTAssertEqual(store.item(tmdbID: 42, kind: .show)?.id, show.id)
        XCTAssertEqual(store.item(tmdbID: 42, kind: .movie)?.id, movie.id)
        XCTAssertNil(store.item(tmdbID: 43, kind: .show))
    }
}
