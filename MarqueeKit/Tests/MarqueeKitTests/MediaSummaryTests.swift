import Foundation
import XCTest
@testable import MarqueeKit

final class MediaSummaryTests: XCTestCase {

    private func makeSummary(kind: MediaKind, genreIDs: [Int], releaseDate: CivilDate? = CivilDate(year: 2024, month: 2, day: 27)) -> MediaSummary {
        MediaSummary(
            id: 693134,
            kind: kind,
            title: "Dune: Part Two",
            overview: "Paul Atreides unites with the Fremen.",
            posterPath: "/poster.jpg",
            backdropPath: nil,
            releaseDate: releaseDate,
            voteAverage: 8.1,
            voteCount: 5432,
            popularity: 1320.7,
            genreIDs: genreIDs,
            originalLanguage: "en"
        )
    }

    // MARK: Derived values

    func testKeyCombinesKindAndID() {
        XCTAssertEqual(makeSummary(kind: .movie, genreIDs: []).key, "movie-693134")
        XCTAssertEqual(makeSummary(kind: .show, genreIDs: []).key, "show-693134")
    }

    func testSameIDDifferentKindAreDifferentValues() {
        let movie = makeSummary(kind: .movie, genreIDs: [])
        let show = makeSummary(kind: .show, genreIDs: [])
        XCTAssertEqual(movie.id, show.id)
        XCTAssertNotEqual(movie, show)
        XCTAssertNotEqual(movie.key, show.key)
        XCTAssertEqual(Set([movie, show]).count, 2)
    }

    func testYear() {
        XCTAssertEqual(makeSummary(kind: .movie, genreIDs: []).year, 2024)
        XCTAssertNil(makeSummary(kind: .movie, genreIDs: [], releaseDate: nil).year)
    }

    func testGenreNamesUseKindTableInOrderAndDropUnknown() {
        let movie = makeSummary(kind: .movie, genreIDs: [878, 12, 424242, 28])
        XCTAssertEqual(movie.genreNames, ["Science Fiction", "Adventure", "Action"])

        let show = makeSummary(kind: .show, genreIDs: [10765, 18, 10759])
        XCTAssertEqual(show.genreNames, ["Sci-Fi & Fantasy", "Drama", "Action & Adventure"])

        XCTAssertEqual(makeSummary(kind: .show, genreIDs: []).genreNames, [])
    }

    func testGenreNamesFallBackToOtherTable() {
        // 878 only exists in the movie table; a show carrying it still resolves.
        XCTAssertEqual(makeSummary(kind: .show, genreIDs: [878]).genreNames, ["Science Fiction"])
        // 10759 only exists in the TV table.
        XCTAssertEqual(makeSummary(kind: .movie, genreIDs: [10759]).genreNames, ["Action & Adventure"])
    }

    // MARK: Codable

    func testCodableRoundTrip() throws {
        let summary = makeSummary(kind: .show, genreIDs: [18])
        let data = try JSONEncoder().encode(summary)
        let decoded = try JSONDecoder().decode(MediaSummary.self, from: data)
        XCTAssertEqual(decoded, summary)
    }

    // MARK: TMDBGenres

    func testGenreTablesAreComplete() {
        XCTAssertEqual(TMDBGenres.tv.count, 16)
        XCTAssertEqual(TMDBGenres.movie.count, 19)
        XCTAssertEqual(TMDBGenres.tv[10759], "Action & Adventure")
        XCTAssertEqual(TMDBGenres.tv[10768], "War & Politics")
        XCTAssertEqual(TMDBGenres.movie[10770], "TV Movie")
        XCTAssertEqual(TMDBGenres.movie[53], "Thriller")
    }

    func testGenreLookups() {
        XCTAssertEqual(TMDBGenres.name(for: 35, kind: .show), "Comedy")
        XCTAssertEqual(TMDBGenres.name(for: 35, kind: .movie), "Comedy")
        XCTAssertEqual(TMDBGenres.name(for: 28, kind: .movie), "Action")
        XCTAssertNil(TMDBGenres.name(for: 28, kind: .show))
        XCTAssertEqual(TMDBGenres.name(for: 28), "Action")
        XCTAssertEqual(TMDBGenres.name(for: 10762), "Kids")
        XCTAssertNil(TMDBGenres.name(for: 1))
    }

    // MARK: SeasonInfo

    func testSeasonInfoDefaultsAndIdentity() {
        let info = SeasonInfo(number: 2, name: "Season 2", episodeCount: 10)
        XCTAssertEqual(info.id, 2)
        XCTAssertNil(info.airDate)
        XCTAssertNil(info.posterPath)
        let full = SeasonInfo(number: 1, name: "Season 1", episodeCount: 9, airDate: CivilDate(year: 2022, month: 2, day: 17), posterPath: "/p.jpg")
        XCTAssertEqual(full.airDate?.year, 2022)
    }
}
