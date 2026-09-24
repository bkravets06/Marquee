import Foundation
import XCTest
@testable import MarqueeKit

final class EpisodePointerTests: XCTestCase {

    func testNotStarted() {
        XCTAssertEqual(EpisodePointer.notStarted, EpisodePointer(season: 0, episode: 0))
        XCTAssertFalse(EpisodePointer.notStarted.isStarted)
        XCTAssertTrue(EpisodePointer(season: 1, episode: 1).isStarted)
        XCTAssertTrue(EpisodePointer(season: 0, episode: 1).isStarted)
    }

    func testLabel() {
        XCTAssertEqual(EpisodePointer(season: 2, episode: 5).label, "S2 E5")
        XCTAssertEqual(EpisodePointer(season: 10, episode: 12).label, "S10 E12")
    }

    func testComparableOrdersBySeasonThenEpisode() {
        XCTAssertTrue(EpisodePointer(season: 1, episode: 9) < EpisodePointer(season: 2, episode: 1))
        XCTAssertTrue(EpisodePointer(season: 2, episode: 1) < EpisodePointer(season: 2, episode: 2))
        XCTAssertFalse(EpisodePointer(season: 2, episode: 2) < EpisodePointer(season: 2, episode: 2))
        let sorted = [
            EpisodePointer(season: 2, episode: 1),
            EpisodePointer(season: 1, episode: 3),
            EpisodePointer.notStarted,
            EpisodePointer(season: 1, episode: 1)
        ].sorted()
        XCTAssertEqual(sorted, [
            EpisodePointer.notStarted,
            EpisodePointer(season: 1, episode: 1),
            EpisodePointer(season: 1, episode: 3),
            EpisodePointer(season: 2, episode: 1)
        ])
    }

    func testCodableRoundTrip() throws {
        let pointer = EpisodePointer(season: 3, episode: 7)
        let data = try JSONEncoder().encode(pointer)
        let decoded = try JSONDecoder().decode(EpisodePointer.self, from: data)
        XCTAssertEqual(decoded, pointer)
    }

    func testDisplayNamesAndSymbols() {
        XCTAssertEqual(MediaKind.show.displayName, "Show")
        XCTAssertEqual(MediaKind.movie.pluralDisplayName, "Movies")
        XCTAssertEqual(MediaKind.show.symbolName, "tv")
        XCTAssertEqual(MediaKind.movie.symbolName, "film")
        XCTAssertEqual(MediaKind.allCases.map { $0.id }, ["show", "movie"])

        XCTAssertEqual(WatchStatus.watching.displayName, "Watching")
        XCTAssertEqual(WatchStatus.watchlist.symbolName, "bookmark")
        XCTAssertEqual(WatchStatus.watched.symbolName, "checkmark.circle")
        XCTAssertEqual(WatchStatus.allCases.map { $0.id }, ["watching", "watchlist", "watched"])
    }
}
