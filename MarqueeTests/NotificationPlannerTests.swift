import XCTest
import SwiftData
import MarqueeKit
@testable import Marquee

// MARK: - NotificationPlannerTests

@MainActor
final class NotificationPlannerTests: XCTestCase {

    /// Keeps the current test's container alive for the duration of the test.
    private var container: ModelContainer?

    private let calendar = Calendar.current

    /// Fixed reference instant: 2026-03-10 08:00 local time.
    private var now: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 10
        components.hour = 8
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? Date(timeIntervalSince1970: 0)
    }

    // MARK: Helpers

    /// The in-memory context for this test, created on first use.
    private func makeContext() throws -> ModelContext {
        if let container {
            return container.mainContext
        }
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: MediaItem.self, configurations: configuration)
        self.container = container
        return container.mainContext
    }

    private func insert(_ item: MediaItem) throws {
        let context = try makeContext()
        context.insert(item)
        try context.save()
    }

    /// Local start of day `days` after `now`.
    private func day(offset days: Int) -> Date {
        let start = calendar.startOfDay(for: now)
        return calendar.date(byAdding: .day, value: days, to: start) ?? start
    }

    @discardableResult
    private func makeTMDBShow(
        title: String = "Test Show",
        tmdbID: Int = 100,
        notificationsEnabled: Bool = true,
        airDate: Date?,
        season: Int? = 2,
        number: Int? = 5,
        episodeName: String? = "The One"
    ) throws -> MediaItem {
        let item = MediaItem(kind: .show, status: .watching, title: title, tmdbID: tmdbID, notificationsEnabled: notificationsEnabled)
        item.nextEpisodeAirDate = airDate
        item.nextEpisodeSeason = season
        item.nextEpisodeNumber = number
        item.nextEpisodeName = episodeName
        try insert(item)
        return item
    }

    @discardableResult
    private func makeCustomShow(
        title: String = "Custom Show",
        notificationsEnabled: Bool = true,
        schedule: ReleaseSchedule?
    ) throws -> MediaItem {
        let item = MediaItem(kind: .show, status: .watching, title: title, isCustom: true, notificationsEnabled: notificationsEnabled)
        item.releaseSchedule = schedule
        try insert(item)
        return item
    }

    private func plan(_ items: [MediaItem], hour: Int = 9, minute: Int = 30) -> [PlannedNotification] {
        NotificationPlanner.plan(items: items, reminderHour: hour, reminderMinute: minute, now: now, calendar: calendar)
    }

    // MARK: TMDB shows

    func testTMDBShowWithFutureEpisodeIsPlanned() throws {
        let airDate = day(offset: 3)
        let item = try makeTMDBShow(title: "Severance", airDate: airDate)

        let planned = plan([item])
        XCTAssertEqual(planned.count, 1)
        let entry = try XCTUnwrap(planned.first)

        let pointer = EpisodePointer(season: 2, episode: 5)
        XCTAssertEqual(entry.id, EpisodeReminder.identifier(itemID: item.id.uuidString, pointer: pointer))
        XCTAssertEqual(entry.id, "marquee.episode.\(item.id.uuidString).S2E5")
        XCTAssertEqual(entry.itemID, item.id)
        XCTAssertFalse(entry.repeats)
        XCTAssertEqual(entry.title, "New episode of Severance")
        XCTAssertEqual(entry.body, EpisodeReminder.body(pointer: pointer, episodeName: "The One"))
        XCTAssertTrue(entry.body.contains("S2 E5"))

        let expected = calendar.dateComponents([.year, .month, .day], from: airDate)
        XCTAssertEqual(entry.dateComponents.year, expected.year)
        XCTAssertEqual(entry.dateComponents.month, expected.month)
        XCTAssertEqual(entry.dateComponents.day, expected.day)
        XCTAssertEqual(entry.dateComponents.hour, 9)
        XCTAssertEqual(entry.dateComponents.minute, 30)
        XCTAssertNil(entry.dateComponents.weekday)
    }

    func testTMDBShowUsesReminderTime() throws {
        let item = try makeTMDBShow(airDate: day(offset: 1))
        let planned = plan([item], hour: 20, minute: 15)
        let entry = try XCTUnwrap(planned.first)
        XCTAssertEqual(entry.dateComponents.hour, 20)
        XCTAssertEqual(entry.dateComponents.minute, 15)
    }

    func testPastAirDateIsSkipped() throws {
        let item = try makeTMDBShow(airDate: day(offset: -2))
        XCTAssertTrue(plan([item]).isEmpty)
    }

    func testTodayIsPlannedOnlyWhenReminderTimeIsStillAhead() throws {
        // `now` is 08:00; a 09:30 reminder is ahead, a 07:00 reminder has passed.
        let item = try makeTMDBShow(airDate: day(offset: 0))
        XCTAssertEqual(plan([item], hour: 9, minute: 30).count, 1)
        XCTAssertTrue(plan([item], hour: 7, minute: 0).isEmpty)
    }

    func testNotificationsDisabledIsIgnored() throws {
        let item = try makeTMDBShow(notificationsEnabled: false, airDate: day(offset: 3))
        XCTAssertTrue(plan([item]).isEmpty)
    }

    func testMissingAirDateOrPointerIsIgnored() throws {
        let noDate = try makeTMDBShow(tmdbID: 1, airDate: nil)
        let noSeason = try makeTMDBShow(tmdbID: 2, airDate: day(offset: 3), season: nil)
        let noNumber = try makeTMDBShow(tmdbID: 3, airDate: day(offset: 3), number: nil)
        XCTAssertTrue(plan([noDate, noSeason, noNumber]).isEmpty)
    }

    func testEpisodeWithoutNameStillHasBody() throws {
        let item = try makeTMDBShow(airDate: day(offset: 3), episodeName: nil)
        let entry = try XCTUnwrap(plan([item]).first)
        XCTAssertEqual(entry.body, "S2 E5 is out today.")
    }

    // MARK: Custom shows

    func testCustomShowWithScheduleIsRepeating() throws {
        let schedule = ReleaseSchedule(weekday: 3, hour: 20, minute: 0)
        let item = try makeCustomShow(title: "Rewatch Club", schedule: schedule)

        let planned = plan([item])
        XCTAssertEqual(planned.count, 1)
        let entry = try XCTUnwrap(planned.first)

        XCTAssertEqual(entry.id, EpisodeReminder.customIdentifier(itemID: item.id.uuidString))
        XCTAssertEqual(entry.id, "marquee.custom.\(item.id.uuidString)")
        XCTAssertEqual(entry.itemID, item.id)
        XCTAssertTrue(entry.repeats)
        XCTAssertEqual(entry.title, "New episode of Rewatch Club")
        XCTAssertEqual(entry.body, "A new episode should be out now.")
        XCTAssertEqual(entry.dateComponents.weekday, 3)
        XCTAssertEqual(entry.dateComponents.hour, 20)
        XCTAssertEqual(entry.dateComponents.minute, 0)
        XCTAssertNil(entry.dateComponents.year)
        XCTAssertNil(entry.dateComponents.day)
    }

    func testCustomShowWithoutScheduleIsIgnored() throws {
        let item = try makeCustomShow(schedule: nil)
        XCTAssertTrue(plan([item]).isEmpty)
    }

    func testCustomShowWithNotificationsDisabledIsIgnored() throws {
        let item = try makeCustomShow(notificationsEnabled: false, schedule: ReleaseSchedule(weekday: 1, hour: 9, minute: 0))
        XCTAssertTrue(plan([item]).isEmpty)
    }

    // MARK: Movies

    func testMovieIsIgnored() throws {
        let movie = MediaItem(kind: .movie, status: .watchlist, title: "Some Movie", tmdbID: 500, notificationsEnabled: true)
        movie.nextEpisodeAirDate = day(offset: 3)
        movie.nextEpisodeSeason = 1
        movie.nextEpisodeNumber = 1
        try insert(movie)

        let customMovie = MediaItem(kind: .movie, status: .watchlist, title: "Home Movie", isCustom: true, notificationsEnabled: true)
        customMovie.releaseSchedule = ReleaseSchedule(weekday: 2, hour: 10, minute: 0)
        try insert(customMovie)

        XCTAssertTrue(plan([movie, customMovie]).isEmpty)
    }

    // MARK: Multiple items

    func testTwoItemsProduceTwoEntriesSortedByIdentifier() throws {
        let first = try makeTMDBShow(title: "Alpha", tmdbID: 1, airDate: day(offset: 2))
        let second = try makeCustomShow(title: "Beta", schedule: ReleaseSchedule(weekday: 5, hour: 21, minute: 30))
        let ignored = try makeTMDBShow(title: "Gamma", tmdbID: 3, airDate: day(offset: -1))

        let planned = plan([second, ignored, first])
        XCTAssertEqual(planned.count, 2)
        XCTAssertEqual(planned.map { $0.id }, planned.map { $0.id }.sorted())
        XCTAssertEqual(Set(planned.map { $0.itemID }), Set([first.id, second.id]))

        // Same input in a different order yields the same output.
        XCTAssertEqual(plan([first, second, ignored]), planned)
    }

    func testEmptyInputProducesEmptyPlan() {
        XCTAssertTrue(plan([]).isEmpty)
    }
}
