import Foundation
import XCTest
@testable import MarqueeKit

final class EpisodeReminderTests: XCTestCase {

    private let calendar = TestSupport.losAngeles

    // MARK: Identifiers

    func testIdentifiers() {
        let pointer = EpisodePointer(season: 2, episode: 5)
        XCTAssertEqual(EpisodeReminder.identifier(itemID: "ABC", pointer: pointer), "marquee.episode.ABC.S2E5")
        XCTAssertEqual(EpisodeReminder.customIdentifier(itemID: "ABC"), "marquee.custom.ABC")
        XCTAssertTrue(EpisodeReminder.identifier(itemID: "x", pointer: pointer).hasPrefix(EpisodeReminder.identifierPrefix))
        XCTAssertTrue(EpisodeReminder.customIdentifier(itemID: "x").hasPrefix(EpisodeReminder.customIdentifierPrefix))
    }

    // MARK: fireComponents

    func testFutureAirDateProducesComponents() {
        let airDate = CivilDate(year: 2026, month: 10, day: 2)
        let components = EpisodeReminder.fireComponents(airDate: airDate, hour: 9, minute: 0, now: TestSupport.referenceNow, calendar: calendar)
        XCTAssertNotNil(components)
        XCTAssertEqual(components?.year, 2026)
        XCTAssertEqual(components?.month, 10)
        XCTAssertEqual(components?.day, 2)
        XCTAssertEqual(components?.hour, 9)
        XCTAssertEqual(components?.minute, 0)
        XCTAssertNil(components?.second)
    }

    func testComponentsResolveToTheExpectedInstant() {
        let airDate = CivilDate(year: 2026, month: 10, day: 2)
        let components = EpisodeReminder.fireComponents(airDate: airDate, hour: 9, minute: 0, now: TestSupport.referenceNow, calendar: calendar)
        let resolved = components.flatMap { calendar.date(from: $0) }
        XCTAssertEqual(resolved?.timeIntervalSince1970, 1_790_956_800)
    }

    func testPastAirDateIsNil() {
        let airDate = CivilDate(year: 2026, month: 9, day: 20)
        XCTAssertNil(EpisodeReminder.fireComponents(airDate: airDate, hour: 9, minute: 0, now: TestSupport.referenceNow, calendar: calendar))
    }

    func testSameDayBeforeReminderTimeIsScheduled() {
        let airDate = CivilDate(year: 2026, month: 10, day: 2)
        let now = Date(timeIntervalSince1970: 1_790_956_740) // 08:59 that morning
        XCTAssertNotNil(EpisodeReminder.fireComponents(airDate: airDate, hour: 9, minute: 0, now: now, calendar: calendar))
    }

    func testSameDayAtOrAfterReminderTimeIsNil() {
        let airDate = CivilDate(year: 2026, month: 10, day: 2)
        let exactly = Date(timeIntervalSince1970: 1_790_956_800) // 09:00 sharp
        XCTAssertNil(EpisodeReminder.fireComponents(airDate: airDate, hour: 9, minute: 0, now: exactly, calendar: calendar))
        let later = Date(timeIntervalSince1970: 1_790_956_800 + 60)
        XCTAssertNil(EpisodeReminder.fireComponents(airDate: airDate, hour: 9, minute: 0, now: later, calendar: calendar))
    }

    // MARK: Text

    func testTitle() {
        XCTAssertEqual(EpisodeReminder.title(showTitle: "Severance"), "New episode of Severance")
    }

    func testBodyWithAndWithoutName() {
        let pointer = EpisodePointer(season: 2, episode: 5)
        XCTAssertEqual(EpisodeReminder.body(pointer: pointer, episodeName: "Cold Harbor"), "S2 E5 \u{201C}Cold Harbor\u{201D} is out today.")
        XCTAssertEqual(EpisodeReminder.body(pointer: pointer, episodeName: nil), "S2 E5 is out today.")
        XCTAssertEqual(EpisodeReminder.body(pointer: pointer, episodeName: "   "), "S2 E5 is out today.")
    }
}
