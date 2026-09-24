import Foundation
import XCTest
@testable import MarqueeKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class RequestBuildingTests: XCTestCase {

    private let token = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ0ZXN0In0.c2lnbmF0dXJl"
    private let apiKey = "0123456789abcdef0123456789abcdef"

    // MARK: Credentials

    func testBearerTokenGoesInAuthorizationHeader() {
        let client = TestSupport.makeClient(credential: .bearer(token))
        let request = client.makeRequest(.tvDetails(id: 1399))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(TestSupport.query(of: request)["api_key"])
    }

    func testAPIKeyGoesInQuery() {
        let client = TestSupport.makeClient(credential: .apiKey(apiKey))
        let request = client.makeRequest(.tvDetails(id: 1399))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(TestSupport.query(of: request)["api_key"], apiKey)
    }

    // MARK: Paths and standard query items

    func testTrendingPathPageAndLanguage() {
        let client = TestSupport.makeClient(language: "de-DE")
        let request = client.makeRequest(.trending(scope: .all, window: .day, page: 2))
        XCTAssertEqual(TestSupport.path(of: request), "/3/trending/all/day")
        let query = TestSupport.query(of: request)
        XCTAssertEqual(query["page"], "2")
        XCTAssertEqual(query["language"], "de-DE")
        XCTAssertNil(query["region"])
        XCTAssertEqual(request.url?.host, "api.themoviedb.org")
        XCTAssertEqual(request.url?.scheme, "https")
    }

    func testTrendingScopesAndWindows() {
        let client = TestSupport.makeClient()
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.trending(scope: .tv, window: .week, page: 1))), "/3/trending/tv/week")
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.trending(scope: .movie, window: .day, page: 1))), "/3/trending/movie/day")
    }

    func testTVListPaths() {
        let client = TestSupport.makeClient()
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.tvList("airing_today", page: 1))), "/3/tv/airing_today")
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.tvList("on_the_air", page: 1))), "/3/tv/on_the_air")
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.tvList("popular", page: 3))), "/3/tv/popular")
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.tvList("top_rated", page: 1))), "/3/tv/top_rated")
    }

    func testDetailPaths() {
        let client = TestSupport.makeClient()
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.tvDetails(id: 95396))), "/3/tv/95396")
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.tvSeason(showID: 95396, number: 2))), "/3/tv/95396/season/2")
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.movieDetails(id: 693134))), "/3/movie/693134")
        XCTAssertEqual(TestSupport.path(of: client.makeRequest(.authentication)), "/3/authentication")
    }

    func testPageIsClampedToAtLeastOne() {
        let client = TestSupport.makeClient()
        XCTAssertEqual(TestSupport.query(of: client.makeRequest(.tvList("popular", page: 0)))["page"], "1")
    }

    // MARK: Region

    func testNowPlayingAndUpcomingIncludeRegion() {
        let client = TestSupport.makeClient(region: "GB")
        let nowPlaying = client.makeRequest(.movieList("now_playing", page: 1, region: "GB"))
        XCTAssertEqual(TestSupport.path(of: nowPlaying), "/3/movie/now_playing")
        XCTAssertEqual(TestSupport.query(of: nowPlaying)["region"], "GB")
        let upcoming = client.makeRequest(.movieList("upcoming", page: 1, region: "GB"))
        XCTAssertEqual(TestSupport.path(of: upcoming), "/3/movie/upcoming")
        XCTAssertEqual(TestSupport.query(of: upcoming)["region"], "GB")
    }

    func testPopularMoviesOmitRegion() {
        let client = TestSupport.makeClient(region: "GB")
        let request = client.makeRequest(.movieList("popular", page: 1))
        XCTAssertEqual(TestSupport.path(of: request), "/3/movie/popular")
        XCTAssertNil(TestSupport.query(of: request)["region"])
    }

    func testNilRegionIsOmittedFromNowPlaying() async throws {
        let recorder = RequestRecorder()
        let client = try TestSupport.makeClient(fixture: "movie_now_playing", region: nil, recorder: recorder)
        _ = try await client.nowPlayingMovies()
        XCTAssertNil(TestSupport.query(of: recorder.last)["region"])
    }

    // MARK: Search

    func testSearchMulti() {
        let client = TestSupport.makeClient()
        let request = client.makeRequest(.search(query: "breaking bad", kind: nil, page: 1))
        XCTAssertEqual(TestSupport.path(of: request), "/3/search/multi")
        let query = TestSupport.query(of: request)
        XCTAssertEqual(query["query"], "breaking bad")
        XCTAssertEqual(query["include_adult"], "false")
        XCTAssertEqual(query["page"], "1")
        XCTAssertEqual(query["language"], "en-US")
    }

    func testSearchByKind() {
        let client = TestSupport.makeClient()
        let shows = client.makeRequest(.search(query: "severance", kind: .show, page: 2))
        XCTAssertEqual(TestSupport.path(of: shows), "/3/search/tv")
        XCTAssertEqual(TestSupport.query(of: shows)["page"], "2")
        XCTAssertEqual(TestSupport.query(of: shows)["include_adult"], "false")
        let movies = client.makeRequest(.search(query: "dune", kind: .movie, page: 1))
        XCTAssertEqual(TestSupport.path(of: movies), "/3/search/movie")
        XCTAssertEqual(TestSupport.query(of: movies)["include_adult"], "false")
    }

    func testSearchQueryIsPercentEncoded() {
        let client = TestSupport.makeClient()
        let request = client.makeRequest(.search(query: "tom & jerry", kind: nil, page: 1))
        let absolute = request.url?.absoluteString ?? ""
        XCTAssertTrue(absolute.contains("query=tom%20"), absolute)
        XCTAssertFalse(absolute.contains(" "), absolute)
        // Parsing the URL back must yield the original query, which proves the ampersand was escaped.
        XCTAssertEqual(TestSupport.query(of: request)["query"], "tom & jerry")
        XCTAssertEqual(TestSupport.queryItems(of: request).count, 4)
    }

    // MARK: Ordering and base URL

    func testQueryItemsAreSortedByName() {
        let client = TestSupport.makeClient(credential: .apiKey(apiKey), region: "US")
        let request = client.makeRequest(.movieList("upcoming", page: 4, region: "US"))
        let names = TestSupport.queryItems(of: request).map { $0.name }
        XCTAssertEqual(names, ["api_key", "language", "page", "region"])
        XCTAssertEqual(names, names.sorted())
    }

    func testDeterministicURL() {
        let client = TestSupport.makeClient(credential: .apiKey(apiKey), language: "en-US")
        let request = client.makeRequest(.search(query: "dune", kind: nil, page: 1))
        XCTAssertEqual(
            request.url?.absoluteString,
            "https://api.themoviedb.org/3/search/multi?api_key=\(apiKey)&include_adult=false&language=en-US&page=1&query=dune"
        )
    }

    func testCustomBaseURLWithTrailingSlash() throws {
        let base = try XCTUnwrap(URL(string: "http://localhost:8080/api/"))
        let client = TestSupport.makeClient(baseURL: base)
        let request = client.makeRequest(.tvDetails(id: 1))
        XCTAssertEqual(request.url?.scheme, "http")
        XCTAssertEqual(request.url?.host, "localhost")
        XCTAssertEqual(request.url?.port, 8080)
        XCTAssertEqual(TestSupport.path(of: request), "/api/tv/1")
    }

    func testPublicInitializerBuildsRequestsWithoutNetwork() {
        let client = TMDBClient(credential: .apiKey(apiKey), language: "fr-FR", region: "FR")
        let request = client.makeRequest(.movieList("upcoming", page: 1, region: "FR"))
        XCTAssertEqual(TestSupport.path(of: request), "/3/movie/upcoming")
        let query = TestSupport.query(of: request)
        XCTAssertEqual(query["api_key"], apiKey)
        XCTAssertEqual(query["language"], "fr-FR")
        XCTAssertEqual(query["region"], "FR")
    }

    // MARK: End-to-end through the public API

    func testPublicMethodsSendExpectedRequests() async throws {
        let recorder = RequestRecorder()
        let tvClient = try TestSupport.makeClient(fixture: "tv_airing_today", region: "CA", recorder: recorder)
        _ = try await tvClient.airingToday(page: 2)
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/tv/airing_today")
        XCTAssertEqual(TestSupport.query(of: recorder.last)["page"], "2")
        _ = try await tvClient.onTheAir()
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/tv/on_the_air")
        _ = try await tvClient.popularShows()
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/tv/popular")
        _ = try await tvClient.topRatedShows()
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/tv/top_rated")
        _ = try await tvClient.search("one piece", kind: .show)
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/search/tv")
        _ = try await tvClient.trending(.tv, window: .week)
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/trending/tv/week")

        let movieClient = try TestSupport.makeClient(fixture: "movie_now_playing", region: "CA", recorder: recorder)
        _ = try await movieClient.nowPlayingMovies()
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/movie/now_playing")
        XCTAssertEqual(TestSupport.query(of: recorder.last)["region"], "CA")
        _ = try await movieClient.upcomingMovies(page: 3)
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/movie/upcoming")
        XCTAssertEqual(TestSupport.query(of: recorder.last)["region"], "CA")
        XCTAssertEqual(TestSupport.query(of: recorder.last)["page"], "3")
        _ = try await movieClient.popularMovies()
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/movie/popular")
        XCTAssertNil(TestSupport.query(of: recorder.last)["region"])
        _ = try await movieClient.topRatedMovies()
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/movie/top_rated")
        _ = try await movieClient.search("dune", kind: .movie)
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/search/movie")
        _ = try await movieClient.trending(.movie)
        XCTAssertEqual(TestSupport.path(of: recorder.last), "/3/trending/movie/day")

        XCTAssertEqual(recorder.requests.count, 12)
        XCTAssertTrue(recorder.requests.allSatisfy { $0.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer ") == true })
        XCTAssertTrue(recorder.requests.allSatisfy { TestSupport.query(of: $0)["language"] == "en-US" })
    }
}
