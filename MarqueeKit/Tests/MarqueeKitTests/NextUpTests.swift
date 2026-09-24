import Foundation
import XCTest
@testable import MarqueeKit

final class NextUpTests: XCTestCase {

    /// Specials, a 10-episode season 1, an empty season 2 and an 8-episode season 3 (deliberately unsorted).
    private let seasons: [SeasonInfo] = [
        SeasonInfo(number: 3, name: "Season 3", episodeCount: 8),
        SeasonInfo(number: 0, name: "Specials", episodeCount: 3),
        SeasonInfo(number: 1, name: "Season 1", episodeCount: 10),
        SeasonInfo(number: 2, name: "Season 2", episodeCount: 0)
    ]

    // MARK: next(after:in:)

    func testNotStartedReturnsFirstRegularEpisode() {
        XCTAssertEqual(NextUp.next(after: .notStarted, in: seasons), EpisodePointer(season: 1, episode: 1))
    }

    func testMidSeasonAdvancesOneEpisode() {
        XCTAssertEqual(NextUp.next(after: EpisodePointer(season: 1, episode: 4), in: seasons), EpisodePointer(season: 1, episode: 5))
        XCTAssertEqual(NextUp.next(after: EpisodePointer(season: 3, episode: 7), in: seasons), EpisodePointer(season: 3, episode: 8))
    }

    func testSeasonRolloverSkipsEmptySeason() {
        XCTAssertEqual(NextUp.next(after: EpisodePointer(season: 1, episode: 10), in: seasons), EpisodePointer(season: 3, episode: 1))
    }

    func testCaughtUpReturnsNil() {
        XCTAssertNil(NextUp.next(after: EpisodePointer(season: 3, episode: 8), in: seasons))
        XCTAssertNil(NextUp.next(after: EpisodePointer(season: 3, episode: 12), in: seasons))
    }

    func testSpecialsAreIgnored() {
        XCTAssertEqual(NextUp.next(after: EpisodePointer(season: 0, episode: 2), in: seasons), EpisodePointer(season: 1, episode: 1))
        let onlySpecials = [SeasonInfo(number: 0, name: "Specials", episodeCount: 4)]
        XCTAssertNil(NextUp.next(after: .notStarted, in: onlySpecials))
    }

    func testEmptySeasonsAreSkipped() {
        let allEmpty = [SeasonInfo(number: 1, name: "Season 1", episodeCount: 0)]
        XCTAssertNil(NextUp.next(after: .notStarted, in: allEmpty))
        // A pointer sitting in the empty season 2 continues with season 3.
        XCTAssertEqual(NextUp.next(after: EpisodePointer(season: 2, episode: 1), in: seasons), EpisodePointer(season: 3, episode: 1))
    }

    func testNoSeasonsReturnsNil() {
        XCTAssertNil(NextUp.next(after: .notStarted, in: []))
        XCTAssertNil(NextUp.next(after: EpisodePointer(season: 1, episode: 1), in: []))
    }

    func testPointerBeyondSeasonEndRollsOver() {
        XCTAssertEqual(NextUp.next(after: EpisodePointer(season: 1, episode: 12), in: seasons), EpisodePointer(season: 3, episode: 1))
    }

    func testPointerInUnknownSeasonContinuesWithNextKnownSeason() {
        XCTAssertEqual(NextUp.next(after: EpisodePointer(season: 5, episode: 1), in: seasons), nil)
        let later = seasons + [SeasonInfo(number: 6, name: "Season 6", episodeCount: 2)]
        XCTAssertEqual(NextUp.next(after: EpisodePointer(season: 5, episode: 1), in: later), EpisodePointer(season: 6, episode: 1))
    }

    // MARK: totalEpisodes(in:)

    func testTotalEpisodesExcludesSpecials() {
        XCTAssertEqual(NextUp.totalEpisodes(in: seasons), 18)
        XCTAssertEqual(NextUp.totalEpisodes(in: []), 0)
    }

    // MARK: watchedCount(upTo:in:)

    func testWatchedCount() {
        XCTAssertEqual(NextUp.watchedCount(upTo: .notStarted, in: seasons), 0)
        XCTAssertEqual(NextUp.watchedCount(upTo: EpisodePointer(season: 1, episode: 4), in: seasons), 4)
        XCTAssertEqual(NextUp.watchedCount(upTo: EpisodePointer(season: 1, episode: 10), in: seasons), 10)
        XCTAssertEqual(NextUp.watchedCount(upTo: EpisodePointer(season: 3, episode: 2), in: seasons), 12)
        XCTAssertEqual(NextUp.watchedCount(upTo: EpisodePointer(season: 3, episode: 8), in: seasons), 18)
    }

    func testWatchedCountClampsToSeasonLength() {
        XCTAssertEqual(NextUp.watchedCount(upTo: EpisodePointer(season: 1, episode: 12), in: seasons), 10)
        XCTAssertEqual(NextUp.watchedCount(upTo: EpisodePointer(season: 0, episode: 3), in: seasons), 0)
    }

    // MARK: previous(before:in:)

    func testPreviousWithinSeason() {
        XCTAssertEqual(NextUp.previous(before: EpisodePointer(season: 3, episode: 5), in: seasons), EpisodePointer(season: 3, episode: 4))
        XCTAssertEqual(NextUp.previous(before: EpisodePointer(season: 1, episode: 2), in: seasons), EpisodePointer(season: 1, episode: 1))
    }

    func testPreviousAcrossSeasonBoundarySkipsEmptySeason() {
        XCTAssertEqual(NextUp.previous(before: EpisodePointer(season: 3, episode: 1), in: seasons), EpisodePointer(season: 1, episode: 10))
    }

    func testPreviousFromFirstEpisodeIsNotStarted() {
        XCTAssertEqual(NextUp.previous(before: EpisodePointer(season: 1, episode: 1), in: seasons), .notStarted)
        XCTAssertEqual(NextUp.previous(before: .notStarted, in: seasons), .notStarted)
        XCTAssertEqual(NextUp.previous(before: EpisodePointer(season: 0, episode: 2), in: seasons), .notStarted)
    }

    func testPreviousClampsPointerBeyondSeasonEnd() {
        XCTAssertEqual(NextUp.previous(before: EpisodePointer(season: 1, episode: 12), in: seasons), EpisodePointer(season: 1, episode: 9))
    }

    func testPreviousWithoutSeasonDataStepsBackOneEpisode() {
        XCTAssertEqual(NextUp.previous(before: EpisodePointer(season: 2, episode: 5), in: []), EpisodePointer(season: 2, episode: 4))
        XCTAssertEqual(NextUp.previous(before: EpisodePointer(season: 2, episode: 1), in: []), .notStarted)
    }
}
