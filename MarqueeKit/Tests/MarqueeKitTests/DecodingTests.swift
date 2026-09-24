import Foundation
import XCTest
@testable import MarqueeKit

final class DecodingTests: XCTestCase {

    // MARK: Mixed lists

    func testTrendingAllDropsPeopleAndMapsKinds() async throws {
        let client = try TestSupport.makeClient(fixture: "trending_all_day")
        let page = try await client.trending(.all, window: .day)

        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.totalPages, 1000)
        XCTAssertEqual(page.totalResults, 20000)
        XCTAssertEqual(page.results.count, 4, "the person row must be dropped")
        XCTAssertEqual(page.results.map { $0.kind }, [.show, .movie, .show, .movie])
        XCTAssertEqual(page.results.map { $0.id }, [94997, 533535, 1399, 693134])
        XCTAssertFalse(page.results.contains { $0.id == 500 })

        let show = page.results[0]
        XCTAssertEqual(show.title, "House of the Dragon")
        XCTAssertEqual(show.releaseDate, CivilDate(year: 2022, month: 8, day: 21))
        XCTAssertEqual(show.genreIDs, [10765, 18, 10759])
        XCTAssertEqual(show.posterPath, "/7QMsOTMUswlwxJP0rTTZfmz2tX2.jpg")
        XCTAssertEqual(show.voteAverage, 8.4, accuracy: 0.001)
        XCTAssertEqual(show.voteCount, 4987)
        XCTAssertEqual(show.originalLanguage, "en")
        XCTAssertEqual(show.key, "show-94997")

        let movie = page.results[1]
        XCTAssertEqual(movie.title, "Deadpool & Wolverine")
        XCTAssertEqual(movie.releaseDate, CivilDate(year: 2024, month: 7, day: 24))
        XCTAssertEqual(movie.year, 2024)
        XCTAssertEqual(movie.key, "movie-533535")
    }

    func testSearchMultiHandlesEmptyDatesAndNulls() async throws {
        let client = try TestSupport.makeClient(fixture: "search_multi")
        let page = try await client.search("severance")

        XCTAssertEqual(page.results.count, 3)
        XCTAssertEqual(page.totalResults, 4, "totalResults stays as reported even after dropping people")
        XCTAssertEqual(page.results.map { $0.kind }, [.show, .movie, .show])

        let movie = page.results[1]
        XCTAssertEqual(movie.title, "Severance")
        XCTAssertNil(movie.backdropPath)
        XCTAssertEqual(movie.releaseDate, CivilDate(year: 2006, month: 8, day: 25))

        let sparse = page.results[2]
        XCTAssertEqual(sparse.title, "Severance Package")
        XCTAssertNil(sparse.releaseDate, "an empty first_air_date decodes as nil")
        XCTAssertNil(sparse.posterPath)
        XCTAssertEqual(sparse.overview, "", "a missing overview becomes an empty string")
        XCTAssertEqual(sparse.genreIDs, [])
        XCTAssertEqual(sparse.voteAverage, 0)
        XCTAssertEqual(sparse.voteCount, 0)
    }

    // MARK: TV and movie lists

    func testAiringTodayDecodesTVRows() async throws {
        let client = try TestSupport.makeClient(fixture: "tv_airing_today")
        let page = try await client.airingToday()

        XCTAssertEqual(page.results.count, 3)
        XCTAssertEqual(page.totalPages, 11)
        XCTAssertEqual(page.totalResults, 214)
        XCTAssertTrue(page.results.allSatisfy { $0.kind == .show })

        let first = page.results[0]
        XCTAssertEqual(first.id, 37854)
        XCTAssertEqual(first.title, "One Piece")
        XCTAssertEqual(first.releaseDate, CivilDate(year: 1999, month: 10, day: 20))
        XCTAssertEqual(first.genreIDs, [16, 10765, 10759])
        XCTAssertEqual(first.originalLanguage, "ja")
        XCTAssertNil(page.results[2].backdropPath)
    }

    func testNowPlayingDecodesMovieRows() async throws {
        let client = try TestSupport.makeClient(fixture: "movie_now_playing")
        let page = try await client.nowPlayingMovies()

        XCTAssertEqual(page.results.count, 3)
        XCTAssertEqual(page.totalPages, 4)
        XCTAssertTrue(page.results.allSatisfy { $0.kind == .movie })
        XCTAssertEqual(page.results[0].title, "Avatar: The Way of Water")
        XCTAssertEqual(page.results[0].releaseDate, CivilDate(year: 2022, month: 12, day: 14))

        let sparse = page.results[2]
        XCTAssertEqual(sparse.overview, "")
        XCTAssertNil(sparse.posterPath)
        XCTAssertNil(sparse.backdropPath)
        XCTAssertEqual(sparse.voteAverage, 0)
        XCTAssertEqual(sparse.releaseDate, CivilDate(year: 2026, month: 9, day: 18))
    }

    // MARK: Show details

    func testTVDetails() async throws {
        let client = try TestSupport.makeClient(fixture: "tv_details")
        let details = try await client.showDetails(id: 95396)

        XCTAssertEqual(details.id, 95396)
        XCTAssertEqual(details.name, "Severance")
        XCTAssertEqual(details.tagline, "Be a team player.")
        XCTAssertEqual(details.status, "Returning Series")
        XCTAssertEqual(details.type, "Scripted")
        XCTAssertTrue(details.inProduction)
        XCTAssertEqual(details.numberOfSeasons, 2)
        XCTAssertEqual(details.numberOfEpisodes, 19)
        XCTAssertEqual(details.episodeRunTime, [])
        XCTAssertEqual(details.firstAirDate, CivilDate(year: 2022, month: 2, day: 17))
        XCTAssertEqual(details.lastAirDate, CivilDate(year: 2025, month: 3, day: 21))
        XCTAssertEqual(details.genres.map { $0.id }, [18, 9648, 10765])
        XCTAssertEqual(details.genres.map { $0.name }, ["Drama", "Mystery", "Sci-Fi & Fantasy"])
        XCTAssertEqual(details.networks.count, 1)
        XCTAssertEqual(details.networks.first?.name, "Apple TV+")
        XCTAssertEqual(details.networks.first?.logoPath, "/4KAy34EHvRM25Ih8wb82AuGU7zJ.png")
        XCTAssertEqual(details.homepage, "https://tv.apple.com/show/severance/umc.cmc.1srk2goyh2q2zdxcx605w8vtx")
        XCTAssertEqual(details.originalLanguage, "en")
        XCTAssertEqual(details.voteAverage, 8.4, accuracy: 0.001)
        XCTAssertEqual(details.voteCount, 2310)
    }

    func testTVDetailsSeasonsAndEpisodes() async throws {
        let client = try TestSupport.makeClient(fixture: "tv_details")
        let details = try await client.showDetails(id: 95396)

        XCTAssertEqual(details.seasons.count, 4, "specials stay in the raw seasons list")
        XCTAssertEqual(details.seasons.map { $0.seasonNumber }, [0, 1, 2, 3])
        XCTAssertEqual(details.seasons[0].name, "Specials")
        XCTAssertNil(details.seasons[3].airDate)
        XCTAssertNil(details.seasons[3].posterPath)

        XCTAssertEqual(details.seasonInfos.map { $0.number }, [1, 2, 3], "specials are excluded from seasonInfos")
        XCTAssertEqual(details.seasonInfos.map { $0.episodeCount }, [9, 10, 0])
        XCTAssertEqual(details.seasonInfos[0].airDate, CivilDate(year: 2022, month: 2, day: 17))
        XCTAssertEqual(details.seasonInfos[0].posterPath, "/5ZUFjeGiY6XIIWuXVvDgUzw3C6Y.jpg")

        let next = try XCTUnwrap(details.nextEpisodeToAir)
        XCTAssertEqual(next.pointer, EpisodePointer(season: 3, episode: 1))
        XCTAssertEqual(next.airDate, CivilDate(year: 2026, month: 10, day: 2))
        XCTAssertEqual(next.name, "")
        XCTAssertNil(next.runtime)
        XCTAssertNil(next.stillPath)
        XCTAssertFalse(next.hasAired(asOf: CivilDate(year: 2026, month: 9, day: 24)))
        XCTAssertTrue(next.hasAired(asOf: CivilDate(year: 2026, month: 10, day: 2)))

        let last = try XCTUnwrap(details.lastEpisodeToAir)
        XCTAssertEqual(last.pointer, EpisodePointer(season: 2, episode: 10))
        XCTAssertEqual(last.name, "Cold Harbor")
        XCTAssertEqual(last.runtime, 76)
        XCTAssertEqual(last.voteAverage ?? 0, 9.1, accuracy: 0.001)
        XCTAssertTrue(last.hasAired(asOf: CivilDate(year: 2026, month: 9, day: 24)))

        XCTAssertEqual(NextUp.next(after: last.pointer, in: details.seasonInfos), nil, "season 3 has no episodes yet")
        XCTAssertEqual(NextUp.totalEpisodes(in: details.seasonInfos), 19)
    }

    func testTVDetailsSummary() async throws {
        let client = try TestSupport.makeClient(fixture: "tv_details")
        let details = try await client.showDetails(id: 95396)
        let summary = details.summary
        XCTAssertEqual(summary.id, 95396)
        XCTAssertEqual(summary.kind, .show)
        XCTAssertEqual(summary.title, "Severance")
        XCTAssertEqual(summary.genreIDs, [18, 9648, 10765])
        XCTAssertEqual(summary.genreNames, ["Drama", "Mystery", "Sci-Fi & Fantasy"])
        XCTAssertEqual(summary.releaseDate, CivilDate(year: 2022, month: 2, day: 17))
        XCTAssertEqual(summary.year, 2022)
        XCTAssertEqual(summary.popularity, 612.348, accuracy: 0.001)
        XCTAssertEqual(summary.posterPath, "/lFf6LLrQjYldcZItzOkGmMMigP7.jpg")
    }

    func testSeasonInfosAreSortedAscending() {
        let details = TVShowDetails(
            id: 1,
            name: "Unsorted",
            overview: "",
            seasons: [
                TVSeasonSummary(id: 3, seasonNumber: 3, name: "Season 3", overview: "", episodeCount: 6),
                TVSeasonSummary(id: 0, seasonNumber: 0, name: "Specials", overview: "", episodeCount: 2),
                TVSeasonSummary(id: 1, seasonNumber: 1, name: "Season 1", overview: "", episodeCount: 8),
                TVSeasonSummary(id: 2, seasonNumber: 2, name: "Season 2", overview: "", episodeCount: 7)
            ]
        )
        XCTAssertEqual(details.seasonInfos.map { $0.number }, [1, 2, 3])
        XCTAssertEqual(details.seasonInfos.map { $0.episodeCount }, [8, 7, 6])
        XCTAssertEqual(details.seasons[1].info, SeasonInfo(number: 0, name: "Specials", episodeCount: 2))
    }

    // MARK: Season details

    func testSeasonDetails() async throws {
        let client = try TestSupport.makeClient(fixture: "tv_season")
        let season = try await client.season(showID: 95396, number: 2)

        XCTAssertEqual(season.id, 386040)
        XCTAssertEqual(season.seasonNumber, 2)
        XCTAssertEqual(season.name, "Season 2")
        XCTAssertEqual(season.overview, "")
        XCTAssertEqual(season.airDate, CivilDate(year: 2025, month: 1, day: 16))
        XCTAssertEqual(season.posterPath, "/lFf6LLrQjYldcZItzOkGmMMigP7.jpg")
        XCTAssertEqual(season.episodes.count, 4)
        XCTAssertEqual(season.episodes.map { $0.episodeNumber }, [1, 2, 3, 4])
        XCTAssertEqual(season.episodes.map { $0.pointer }, [
            EpisodePointer(season: 2, episode: 1),
            EpisodePointer(season: 2, episode: 2),
            EpisodePointer(season: 2, episode: 3),
            EpisodePointer(season: 2, episode: 4)
        ])

        let first = season.episodes[0]
        XCTAssertEqual(first.name, "Hello, Ms. Cobel")
        XCTAssertEqual(first.runtime, 55)
        XCTAssertEqual(first.stillPath, "/aB2rM5Ve3f1oS7fhRZ8Yn6rJCsz.jpg")
        XCTAssertEqual(first.voteAverage ?? 0, 8.0, accuracy: 0.001)

        let third = season.episodes[2]
        XCTAssertEqual(third.overview, "", "a null overview becomes an empty string")
        XCTAssertNil(third.stillPath)

        let fourth = season.episodes[3]
        XCTAssertNil(fourth.airDate)
        XCTAssertNil(fourth.runtime)
        XCTAssertFalse(fourth.hasAired(asOf: CivilDate(year: 2030, month: 1, day: 1)), "no air date means not aired")

        let today = CivilDate(year: 2025, month: 1, day: 23)
        XCTAssertEqual(season.episodes.map { $0.hasAired(asOf: today) }, [true, true, false, false])
    }

    // MARK: Movie details

    func testMovieDetails() async throws {
        let client = try TestSupport.makeClient(fixture: "movie_details")
        let movie = try await client.movieDetails(id: 693134)

        XCTAssertEqual(movie.id, 693134)
        XCTAssertEqual(movie.title, "Dune: Part Two")
        XCTAssertEqual(movie.tagline, "Long live the fighters.")
        XCTAssertEqual(movie.runtime, 167)
        XCTAssertEqual(movie.imdbID, "tt15239678")
        XCTAssertEqual(movie.status, "Released")
        XCTAssertEqual(movie.releaseDate, CivilDate(year: 2024, month: 2, day: 27))
        XCTAssertEqual(movie.genres.map { $0.id }, [878, 12])
        XCTAssertEqual(movie.homepage, "https://www.dunemovie.com")
        XCTAssertEqual(movie.originalLanguage, "en")
        XCTAssertEqual(movie.voteAverage, 8.1, accuracy: 0.001)
        XCTAssertEqual(movie.voteCount, 5432)

        let summary = movie.summary
        XCTAssertEqual(summary.kind, .movie)
        XCTAssertEqual(summary.title, "Dune: Part Two")
        XCTAssertEqual(summary.genreIDs, [878, 12])
        XCTAssertEqual(summary.genreNames, ["Science Fiction", "Adventure"])
        XCTAssertEqual(summary.year, 2024)
        XCTAssertEqual(summary.key, "movie-693134")
    }

    // MARK: Leniency and round trips

    func testMissingFieldsFallBackToDefaults() throws {
        let json = Data("{\"id\": 42}".utf8)
        let decoder = JSONDecoder()

        let show = try decoder.decode(TVShowDetails.self, from: json)
        XCTAssertEqual(show.id, 42)
        XCTAssertEqual(show.name, "")
        XCTAssertEqual(show.overview, "")
        XCTAssertNil(show.tagline)
        XCTAssertEqual(show.genres, [])
        XCTAssertEqual(show.seasons, [])
        XCTAssertEqual(show.networks, [])
        XCTAssertEqual(show.episodeRunTime, [])
        XCTAssertEqual(show.numberOfEpisodes, 0)
        XCTAssertEqual(show.voteAverage, 0)
        XCTAssertFalse(show.inProduction)
        XCTAssertNil(show.nextEpisodeToAir)
        XCTAssertNil(show.firstAirDate)

        let movie = try decoder.decode(MovieDetails.self, from: json)
        XCTAssertEqual(movie.title, "")
        XCTAssertNil(movie.runtime)
        XCTAssertEqual(movie.genres, [])

        let season = try decoder.decode(SeasonDetails.self, from: json)
        XCTAssertEqual(season.episodes, [])

        let episode = try decoder.decode(EpisodeSummary.self, from: json)
        XCTAssertEqual(episode.pointer, EpisodePointer(season: 0, episode: 0))
    }

    func testMissingIDIsAnError() {
        let json = Data("{\"name\": \"No id\"}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(TVShowDetails.self, from: json))
        XCTAssertThrowsError(try JSONDecoder().decode(MovieDetails.self, from: json))
    }

    func testEmptyAndNullTaglineBecomeNil() throws {
        let empty = try JSONDecoder().decode(MovieDetails.self, from: Data("{\"id\": 1, \"tagline\": \"\"}".utf8))
        XCTAssertNil(empty.tagline)
        let null = try JSONDecoder().decode(MovieDetails.self, from: Data("{\"id\": 1, \"tagline\": null}".utf8))
        XCTAssertNil(null.tagline)
    }

    func testPagedResponseRequiresResults() {
        let json = Data("{\"page\": 1}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PagedResponse<Genre>.self, from: json))
    }

    func testPagedResponseDefaultsPagingFields() throws {
        let json = Data("{\"results\": [{\"id\": 18, \"name\": \"Drama\"}]}".utf8)
        let page = try JSONDecoder().decode(PagedResponse<Genre>.self, from: json)
        XCTAssertEqual(page.page, 1)
        XCTAssertEqual(page.totalPages, 1)
        XCTAssertEqual(page.totalResults, 0)
        XCTAssertEqual(page.results, [Genre(id: 18, name: "Drama")])
    }

    func testDetailsSurviveEncodeDecodeRoundTrip() async throws {
        let showClient = try TestSupport.makeClient(fixture: "tv_details")
        let show = try await showClient.showDetails(id: 95396)
        let showData = try JSONEncoder().encode(show)
        XCTAssertEqual(try JSONDecoder().decode(TVShowDetails.self, from: showData), show)

        let movieClient = try TestSupport.makeClient(fixture: "movie_details")
        let movie = try await movieClient.movieDetails(id: 693134)
        let movieData = try JSONEncoder().encode(movie)
        XCTAssertEqual(try JSONDecoder().decode(MovieDetails.self, from: movieData), movie)

        let seasonClient = try TestSupport.makeClient(fixture: "tv_season")
        let season = try await seasonClient.season(showID: 95396, number: 2)
        let seasonData = try JSONEncoder().encode(season)
        XCTAssertEqual(try JSONDecoder().decode(SeasonDetails.self, from: seasonData), season)
    }

    func testMediaSummaryCodableRoundTrip() async throws {
        let client = try TestSupport.makeClient(fixture: "trending_all_day")
        let page = try await client.trending()
        let data = try JSONEncoder().encode(page)
        let decoded = try JSONDecoder().decode(PagedResponse<MediaSummary>.self, from: data)
        XCTAssertEqual(decoded.results, page.results)
        XCTAssertEqual(decoded.totalResults, page.totalResults)
    }

    func testErrorFixtureDecodesAsStatusEnvelope() throws {
        let envelope = try JSONDecoder().decode(TMDBStatusResponse.self, from: TestSupport.fixtureData("error_401"))
        XCTAssertEqual(envelope.success, false)
        XCTAssertEqual(envelope.statusCode, 7)
        XCTAssertEqual(envelope.statusMessage, "Invalid API key: You must be granted a valid key.")
    }
}
