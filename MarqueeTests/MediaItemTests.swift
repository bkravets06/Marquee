import XCTest
import SwiftData
import MarqueeKit
@testable import Marquee

// MARK: - MediaItemTests

@MainActor
final class MediaItemTests: XCTestCase {

    /// Keeps the current test's container alive for the duration of the test.
    private var container: ModelContainer?

    // MARK: Helpers

    private func makeContext() throws -> ModelContext {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MediaItem.self, configurations: configuration)
        self.container = container
        return container.mainContext
    }

    private func insertShow(
        into context: ModelContext,
        seasons: [SeasonInfo],
        progress: EpisodePointer = .notStarted,
        isCustom: Bool = false,
        totalEpisodes: Int? = nil
    ) -> MediaItem {
        let item = MediaItem(
            kind: .show,
            status: .watching,
            title: "Show",
            tmdbID: isCustom ? nil : 7,
            totalEpisodes: totalEpisodes,
            isCustom: isCustom
        )
        item.seasons = seasons
        item.progress = progress
        context.insert(item)
        return item
    }

    private func startOfDay(offsetDays: Int, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: .now)
        return calendar.date(byAdding: .day, value: offsetDays, to: today) ?? today
    }

    // MARK: Typed accessors

    func testKindAndStatusAccessors() throws {
        let context = try makeContext()
        let item = MediaItem(kind: .movie, status: .watchlist, title: "Movie")
        context.insert(item)

        XCTAssertEqual(item.kindRaw, MediaKind.movie.rawValue)
        XCTAssertEqual(item.statusRaw, WatchStatus.watchlist.rawValue)
        XCTAssertTrue(item.isMovie)
        XCTAssertFalse(item.isShow)

        item.kind = .show
        item.status = .watched
        XCTAssertEqual(item.kindRaw, "show")
        XCTAssertEqual(item.statusRaw, "watched")
        XCTAssertTrue(item.isShow)
    }

    func testSeasonsRoundTrip() throws {
        let context = try makeContext()
        let item = MediaItem(kind: .show, status: .watching, title: "Show")
        context.insert(item)
        XCTAssertTrue(item.seasons.isEmpty)
        XCTAssertNil(item.seasonsData)

        let seasons = [
            SeasonInfo(number: 1, name: "Season 1", episodeCount: 8, airDate: CivilDate(year: 2020, month: 5, day: 1), posterPath: "/s1.jpg"),
            SeasonInfo(number: 2, name: "Season 2", episodeCount: 10)
        ]
        item.seasons = seasons
        XCTAssertNotNil(item.seasonsData)
        XCTAssertEqual(item.seasons, seasons)

        item.seasons = []
        XCTAssertNil(item.seasonsData)
        XCTAssertTrue(item.seasons.isEmpty)
    }

    func testReleaseScheduleRoundTrip() throws {
        let context = try makeContext()
        let item = MediaItem(kind: .show, status: .watching, title: "Custom", isCustom: true)
        context.insert(item)
        XCTAssertNil(item.releaseSchedule)

        let schedule = ReleaseSchedule(weekday: 5, hour: 21, minute: 15)
        item.releaseSchedule = schedule
        XCTAssertEqual(item.releaseSchedule, schedule)

        item.releaseSchedule = nil
        XCTAssertNil(item.releaseScheduleData)
    }

    func testProgressAccessor() throws {
        let context = try makeContext()
        let item = MediaItem(kind: .show, status: .watching, title: "Show")
        context.insert(item)
        XCTAssertEqual(item.progress, .notStarted)

        item.progress = EpisodePointer(season: 3, episode: 4)
        XCTAssertEqual(item.progressSeason, 3)
        XCTAssertEqual(item.progressEpisode, 4)
        XCTAssertEqual(item.progress.label, "S3 E4")
    }

    // MARK: Progress math

    func testProgressFraction() throws {
        let context = try makeContext()

        let halfway = insertShow(
            into: context,
            seasons: [SeasonInfo(number: 1, name: "Season 1", episodeCount: 10)],
            progress: EpisodePointer(season: 1, episode: 5)
        )
        XCTAssertEqual(halfway.watchedEpisodeCount, 5)
        XCTAssertEqual(halfway.episodeTotal, 10)
        XCTAssertEqual(try XCTUnwrap(halfway.progressFraction), 0.5, accuracy: 0.001)

        let unknown = insertShow(into: context, seasons: [])
        XCTAssertNil(unknown.episodeTotal)
        XCTAssertNil(unknown.progressFraction)

        let custom = insertShow(
            into: context,
            seasons: [],
            progress: EpisodePointer(season: 1, episode: 2),
            isCustom: true,
            totalEpisodes: 8
        )
        XCTAssertEqual(custom.watchedEpisodeCount, 2)
        XCTAssertEqual(custom.episodeTotal, 8)
        XCTAssertEqual(try XCTUnwrap(custom.progressFraction), 0.25, accuracy: 0.001)

        let done = insertShow(
            into: context,
            seasons: [
                SeasonInfo(number: 1, name: "Season 1", episodeCount: 2),
                SeasonInfo(number: 2, name: "Season 2", episodeCount: 2)
            ],
            progress: EpisodePointer(season: 2, episode: 2)
        )
        XCTAssertEqual(try XCTUnwrap(done.progressFraction), 1.0, accuracy: 0.001)
        XCTAssertNil(done.nextUp)
    }

    func testNextUpForTMDBShow() throws {
        let context = try makeContext()
        let seasons = [
            SeasonInfo(number: 1, name: "Season 1", episodeCount: 2),
            SeasonInfo(number: 2, name: "Season 2", episodeCount: 2)
        ]
        let fresh = insertShow(into: context, seasons: seasons)
        XCTAssertEqual(fresh.nextUp, EpisodePointer(season: 1, episode: 1))

        let rollover = insertShow(into: context, seasons: seasons, progress: EpisodePointer(season: 1, episode: 2))
        XCTAssertEqual(rollover.nextUp, EpisodePointer(season: 2, episode: 1))

        let noSeasons = insertShow(into: context, seasons: [])
        XCTAssertNil(noSeasons.nextUp)
    }

    func testNextUpForCustomShow() throws {
        let context = try makeContext()

        let fresh = insertShow(into: context, seasons: [], isCustom: true)
        XCTAssertEqual(fresh.nextUp, EpisodePointer(season: 1, episode: 1))

        let midway = insertShow(into: context, seasons: [], progress: EpisodePointer(season: 1, episode: 3), isCustom: true)
        XCTAssertEqual(midway.nextUp, EpisodePointer(season: 1, episode: 4))

        let finished = insertShow(into: context, seasons: [], progress: EpisodePointer(season: 1, episode: 3), isCustom: true, totalEpisodes: 3)
        XCTAssertNil(finished.nextUp)

        let seasonTwo = insertShow(into: context, seasons: [], progress: EpisodePointer(season: 2, episode: 1), isCustom: true)
        XCTAssertEqual(seasonTwo.nextUp, EpisodePointer(season: 2, episode: 2))
    }

    // MARK: Next episode

    func testNextEpisodeLabel() throws {
        let context = try makeContext()
        let item = insertShow(into: context, seasons: [SeasonInfo(number: 1, name: "Season 1", episodeCount: 10)])
        XCTAssertNil(item.nextEpisodeLabel)
        XCTAssertNil(item.nextEpisodePointer)

        item.nextEpisodeSeason = 2
        item.nextEpisodeNumber = 5
        XCTAssertEqual(item.nextEpisodePointer, EpisodePointer(season: 2, episode: 5))
        XCTAssertEqual(item.nextEpisodeLabel, "S2 E5")

        item.nextEpisodeAirDate = startOfDay(offsetDays: 1)
        let label = try XCTUnwrap(item.nextEpisodeLabel)
        XCTAssertTrue(label.hasPrefix("S2 E5"))
        XCTAssertTrue(label.contains("Tomorrow"))

        item.nextEpisodeSeason = nil
        item.nextEpisodeNumber = nil
        XCTAssertEqual(item.nextEpisodeLabel, "Tomorrow")
    }

    func testNextEpisodeLabelForCustomShowUsesSchedule() throws {
        let context = try makeContext()
        let item = insertShow(into: context, seasons: [], progress: EpisodePointer(season: 1, episode: 2), isCustom: true)
        XCTAssertNil(item.nextEpisodeLabel)

        item.releaseSchedule = ReleaseSchedule(weekday: 3, hour: 20, minute: 0)
        let label = try XCTUnwrap(item.nextEpisodeLabel)
        XCTAssertTrue(label.hasPrefix("S1 E3"))
    }

    func testAirsWithinDays() throws {
        let context = try makeContext()
        let item = insertShow(into: context, seasons: [])
        XCTAssertFalse(item.airsWithinDays(7))

        item.nextEpisodeAirDate = startOfDay(offsetDays: 2)
        XCTAssertTrue(item.airsWithinDays(7))
        XCTAssertTrue(item.airsWithinDays(2))
        XCTAssertFalse(item.airsWithinDays(1))

        item.nextEpisodeAirDate = startOfDay(offsetDays: 0)
        XCTAssertTrue(item.airsWithinDays(0))
        XCTAssertTrue(item.airsWithinDays(7))

        item.nextEpisodeAirDate = startOfDay(offsetDays: -1)
        XCTAssertFalse(item.airsWithinDays(7))

        item.nextEpisodeAirDate = startOfDay(offsetDays: 8)
        XCTAssertFalse(item.airsWithinDays(7))
    }

    // MARK: Metadata

    func testYearAndImageURLs() throws {
        let context = try makeContext()
        let item = MediaItem(
            kind: .movie,
            status: .watchlist,
            title: "Movie",
            posterPath: "/poster.jpg",
            backdropPath: "/backdrop.jpg",
            releaseDate: CivilDate(year: 2019, month: 11, day: 8).startOfDay()
        )
        context.insert(item)

        XCTAssertEqual(item.year, 2019)
        let poster = try XCTUnwrap(item.posterURL())
        XCTAssertTrue(poster.absoluteString.hasSuffix("/poster.jpg"))
        XCTAssertTrue(poster.absoluteString.contains("w342"))
        let backdrop = try XCTUnwrap(item.backdropURL(size: .w1280))
        XCTAssertTrue(backdrop.absoluteString.hasSuffix("/backdrop.jpg"))
        XCTAssertTrue(backdrop.absoluteString.contains("w1280"))

        let custom = MediaItem(kind: .show, status: .watching, title: "Custom", isCustom: true)
        context.insert(custom)
        XCTAssertNil(custom.year)
        XCTAssertNil(custom.posterURL())
        XCTAssertNil(custom.backdropURL())
    }

    func testInitDefaults() throws {
        let context = try makeContext()
        let before = Date.now
        let item = MediaItem(kind: .show, status: .watchlist, title: "X")
        context.insert(item)

        XCTAssertNil(item.tmdbID)
        XCTAssertEqual(item.overview, "")
        XCTAssertEqual(item.notes, "")
        XCTAssertTrue(item.genres.isEmpty)
        XCTAssertEqual(item.progress, .notStarted)
        XCTAssertFalse(item.notificationsEnabled)
        XCTAssertFalse(item.isCustom)
        XCTAssertNil(item.userRating)
        XCTAssertGreaterThanOrEqual(item.addedAt, before)
        XCTAssertEqual(item.addedAt, item.updatedAt)
    }

    // MARK: Formatters

    func testRuntimeFormatting() {
        XCTAssertEqual(Formatters.runtime(minutes: 102), "1h 42m")
        XCTAssertEqual(Formatters.runtime(minutes: 48), "48m")
        XCTAssertEqual(Formatters.runtime(minutes: 120), "2h")
        XCTAssertEqual(Formatters.runtime(minutes: 0), "0m")
    }

    func testYearFormatting() {
        XCTAssertNil(Formatters.year(from: nil))
        let date = CivilDate(year: 2024, month: 3, day: 1).startOfDay()
        XCTAssertEqual(Formatters.year(from: date), "2024")
    }

    func testRelativeAirDate() {
        let calendar = Calendar.current
        let now = Date.now

        XCTAssertEqual(Formatters.relativeAirDate(now, now: now, calendar: calendar), "Today")
        XCTAssertEqual(Formatters.relativeAirDate(startOfDay(offsetDays: 1), now: now, calendar: calendar), "Tomorrow")
        XCTAssertEqual(Formatters.relativeAirDate(startOfDay(offsetDays: -1), now: now, calendar: calendar), "Yesterday")

        let weekday = Formatters.relativeAirDate(startOfDay(offsetDays: 3), now: now, calendar: calendar)
        XCTAssertFalse(weekday.isEmpty)
        XCTAssertNotEqual(weekday, "Today")
        XCTAssertNotEqual(weekday, "Tomorrow")
        XCTAssertNil(weekday.rangeOfCharacter(from: .decimalDigits))

        let farOut = Formatters.relativeAirDate(startOfDay(offsetDays: 30), now: now, calendar: calendar)
        XCTAssertNotNil(farOut.rangeOfCharacter(from: .decimalDigits))

        let nextYear = startOfDay(offsetDays: 400)
        let nextYearLabel = Formatters.relativeAirDate(nextYear, now: now, calendar: calendar)
        let year = String(calendar.component(.year, from: nextYear))
        XCTAssertTrue(nextYearLabel.contains(year))
    }

    func testUpdatedAgo() {
        XCTAssertEqual(Formatters.updatedAgo(nil), "Never updated")
        let now = Date.now
        let label = Formatters.updatedAgo(now.addingTimeInterval(-3 * 3_600), now: now)
        XCTAssertTrue(label.hasPrefix("Updated "))
    }
}
