import Foundation
import XCTest
@testable import MarqueeKit

final class ReleaseScheduleTests: XCTestCase {

    private let calendar = TestSupport.losAngeles
    /// Tuesdays at 8:00 PM.
    private let schedule = ReleaseSchedule(weekday: 3, hour: 20, minute: 0)

    // MARK: nextOccurrence(after:calendar:)

    func testNextOccurrenceLaterInTheWeek() {
        // Thursday 2026-09-24 10:00 -> Tuesday 2026-09-29 20:00
        let after = Date(timeIntervalSince1970: 1_790_269_200)
        let next = schedule.nextOccurrence(after: after, calendar: calendar)
        XCTAssertEqual(next?.timeIntervalSince1970, 1_790_737_200)
        let components = calendar.dateComponents([.weekday, .hour, .minute], from: next ?? Date())
        XCTAssertEqual(components.weekday, 3)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 0)
    }

    func testNextOccurrenceSameDayWhenStillAhead() {
        // Tuesday 2026-09-29 19:59 -> the same evening at 20:00
        let after = Date(timeIntervalSince1970: 1_790_737_140)
        XCTAssertEqual(schedule.nextOccurrence(after: after, calendar: calendar)?.timeIntervalSince1970, 1_790_737_200)
    }

    func testNextOccurrenceIsStrictlyAfter() {
        // Exactly Tuesday 2026-09-29 20:00 -> the following Tuesday
        let after = Date(timeIntervalSince1970: 1_790_737_200)
        XCTAssertEqual(schedule.nextOccurrence(after: after, calendar: calendar)?.timeIntervalSince1970, 1_791_342_000)
    }

    func testNextOccurrenceAcrossDaylightSavingChange() {
        // Saturday 2026-10-31 10:00 PDT -> Tuesday 2026-11-03 20:00 PST
        let after = Date(timeIntervalSince1970: 1_793_466_000)
        let next = schedule.nextOccurrence(after: after, calendar: calendar)
        XCTAssertEqual(next?.timeIntervalSince1970, 1_793_764_800)
        let components = calendar.dateComponents([.month, .day, .hour], from: next ?? Date())
        XCTAssertEqual(components.month, 11)
        XCTAssertEqual(components.day, 3)
        XCTAssertEqual(components.hour, 20)
    }

    func testNextOccurrenceForEveryWeekdayLandsOnThatWeekday() {
        let after = TestSupport.referenceNow
        for weekday in 1...7 {
            let candidate = ReleaseSchedule(weekday: weekday, hour: 9, minute: 30)
            let next = candidate.nextOccurrence(after: after, calendar: calendar)
            XCTAssertNotNil(next, "weekday \(weekday)")
            guard let date = next else { continue }
            XCTAssertGreaterThan(date, after)
            XCTAssertLessThanOrEqual(date.timeIntervalSince(after), 7 * 24 * 3_600)
            let components = calendar.dateComponents([.weekday, .hour, .minute], from: date)
            XCTAssertEqual(components.weekday, weekday)
            XCTAssertEqual(components.hour, 9)
            XCTAssertEqual(components.minute, 30)
        }
    }

    // MARK: dateComponents

    func testDateComponentsCarryOnlyWeekdayHourMinute() {
        let components = schedule.dateComponents
        XCTAssertEqual(components.weekday, 3)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 0)
        XCTAssertNil(components.year)
        XCTAssertNil(components.month)
        XCTAssertNil(components.day)
    }

    // MARK: summary(calendar:)

    func testSummaryUsesPluralWeekdayAndShortTime() {
        let summary = schedule.summary(calendar: calendar)
        XCTAssertTrue(summary.hasPrefix("Tuesdays at "), summary)
        XCTAssertTrue(summary.contains("8:00"), summary)
    }

    func testSummaryForOtherWeekdays() {
        XCTAssertTrue(ReleaseSchedule(weekday: 1, hour: 9, minute: 5).summary(calendar: calendar).hasPrefix("Sundays at "))
        XCTAssertTrue(ReleaseSchedule(weekday: 7, hour: 0, minute: 0).summary(calendar: calendar).hasPrefix("Saturdays at "))
        XCTAssertTrue(ReleaseSchedule(weekday: 4, hour: 21, minute: 30).summary(calendar: calendar).contains("9:30"))
    }

    // MARK: Codable

    func testCodableRoundTrip() throws {
        let data = try JSONEncoder().encode(schedule)
        let decoded = try JSONDecoder().decode(ReleaseSchedule.self, from: data)
        XCTAssertEqual(decoded, schedule)
    }
}
