import Foundation
import XCTest
@testable import MarqueeKit

final class CivilDateTests: XCTestCase {

    // MARK: Parsing

    func testParsesValidString() {
        let date = CivilDate("2026-09-30")
        XCTAssertEqual(date, CivilDate(year: 2026, month: 9, day: 30))
    }

    func testEmptyStringIsNil() {
        XCTAssertNil(CivilDate(""))
        XCTAssertNil(CivilDate("   "))
    }

    func testInvalidStringsAreNil() {
        XCTAssertNil(CivilDate("2026-13-01"))
        XCTAssertNil(CivilDate("2026-00-10"))
        XCTAssertNil(CivilDate("2026-02-30"))
        XCTAssertNil(CivilDate("2026-04-31"))
        XCTAssertNil(CivilDate("abc"))
        XCTAssertNil(CivilDate("2026/09/30"))
        XCTAssertNil(CivilDate("26-09-30"))
        XCTAssertNil(CivilDate("2026-9-30"))
        XCTAssertNil(CivilDate("2026-09-30T00:00:00"))
    }

    func testLeapDays() {
        XCTAssertEqual(CivilDate("2024-02-29"), CivilDate(year: 2024, month: 2, day: 29))
        XCTAssertNil(CivilDate("2026-02-29"))
        XCTAssertNil(CivilDate("1900-02-29"))
        XCTAssertNotNil(CivilDate("2000-02-29"))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(CivilDate(" 2026-09-30\n"), CivilDate(year: 2026, month: 9, day: 30))
    }

    // MARK: Formatting

    func testStringRoundTrip() {
        let date = CivilDate(year: 2026, month: 1, day: 5)
        XCTAssertEqual(date.string, "2026-01-05")
        XCTAssertEqual(date.description, "2026-01-05")
        XCTAssertEqual(CivilDate(date.string), date)
    }

    // MARK: Comparable

    func testComparable() {
        let earlier = CivilDate(year: 2025, month: 12, day: 31)
        let later = CivilDate(year: 2026, month: 1, day: 1)
        XCTAssertTrue(earlier < later)
        XCTAssertFalse(later < earlier)
        XCTAssertTrue(CivilDate(year: 2026, month: 3, day: 1) < CivilDate(year: 2026, month: 3, day: 2))
        XCTAssertTrue(CivilDate(year: 2026, month: 2, day: 28) < CivilDate(year: 2026, month: 3, day: 1))
        XCTAssertTrue(later <= later)
        XCTAssertEqual([later, earlier].sorted(), [earlier, later])
    }

    // MARK: Codable

    func testEncodesAsString() throws {
        let data = try JSONEncoder().encode([CivilDate(year: 2026, month: 9, day: 30)])
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "[\"2026-09-30\"]")
    }

    func testDecodesFromString() throws {
        let data = Data("[\"2026-09-30\"]".utf8)
        let dates = try JSONDecoder().decode([CivilDate].self, from: data)
        XCTAssertEqual(dates, [CivilDate(year: 2026, month: 9, day: 30)])
    }

    func testDecodingEmptyStringThrows() {
        let data = Data("[\"\"]".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([CivilDate].self, from: data))
    }

    func testDecodingGarbageThrows() {
        let data = Data("[\"not a date\"]".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode([CivilDate].self, from: data))
    }

    // MARK: Calendar conversion

    func testStartOfDayInLosAngeles() {
        let calendar = TestSupport.losAngeles
        let date = CivilDate(year: 2026, month: 9, day: 30)
        XCTAssertEqual(date.startOfDay(in: calendar)?.timeIntervalSince1970, 1_790_751_600)
        XCTAssertEqual(date.date(in: calendar)?.timeIntervalSince1970, 1_790_751_600)
    }

    func testDateAtHourAndMinute() {
        let calendar = TestSupport.losAngeles
        let date = CivilDate(year: 2026, month: 9, day: 30)
        let moment = date.date(in: calendar, hour: 20, minute: 15)
        let expected: Double = 1_790_751_600 + 20 * 3_600 + 15 * 60
        XCTAssertEqual(moment?.timeIntervalSince1970, expected)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: moment ?? Date())
        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 9)
        XCTAssertEqual(components.day, 30)
        XCTAssertEqual(components.hour, 20)
        XCTAssertEqual(components.minute, 15)
    }

    func testInitFromDateDependsOnCalendarTimeZone() {
        // 2026-09-29 23:00 in Los Angeles is 2026-09-30 06:00 UTC.
        let instant = Date(timeIntervalSince1970: 1_790_751_600 - 3_600)
        XCTAssertEqual(CivilDate(instant, calendar: TestSupport.losAngeles), CivilDate(year: 2026, month: 9, day: 29))

        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0)!
        XCTAssertEqual(CivilDate(instant, calendar: utc), CivilDate(year: 2026, month: 9, day: 30))
    }

    func testTodayIsPlausible() {
        let today = CivilDate.today(calendar: TestSupport.losAngeles)
        XCTAssertGreaterThanOrEqual(today.year, 2026)
        XCTAssertTrue((1...12).contains(today.month))
        XCTAssertTrue((1...31).contains(today.day))
    }
}
