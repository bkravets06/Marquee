import Foundation
import XCTest
@testable import MarqueeKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class ErrorMappingTests: XCTestCase {

    // MARK: HTTP status mapping

    func testUnauthorized() async throws {
        let client = try TestSupport.makeClient(fixture: "error_401", status: 401)
        let error = await TestSupport.capturedError { try await client.showDetails(id: 1) }
        XCTAssertEqual(error, .unauthorized)
        XCTAssertEqual(error?.errorDescription, "Your TMDB API key was rejected.")
    }

    func testValidateCredentialsRejected() async throws {
        let client = try TestSupport.makeClient(fixture: "error_401", status: 401)
        let error = await TestSupport.capturedError { try await client.validateCredentials() }
        XCTAssertEqual(error, .unauthorized)
    }

    func testNotFound() async {
        let body = Data("{\"success\":false,\"status_code\":34,\"status_message\":\"The resource you requested could not be found.\"}".utf8)
        let client = TestSupport.makeClient(status: 404, body: body)
        let error = await TestSupport.capturedError { try await client.movieDetails(id: 999_999_999) }
        XCTAssertEqual(error, .notFound)
    }

    func testRateLimitedParsesRetryAfter() async {
        let client = TestSupport.makeClient(status: 429, headers: ["Retry-After": "7"])
        let error = await TestSupport.capturedError { try await client.popularShows() }
        XCTAssertEqual(error, .rateLimited(retryAfter: 7))
        XCTAssertTrue(error?.errorDescription?.contains("7") == true)
    }

    func testRateLimitedWithoutHeader() async {
        let client = TestSupport.makeClient(status: 429)
        let error = await TestSupport.capturedError { try await client.popularShows() }
        XCTAssertEqual(error, .rateLimited(retryAfter: nil))
    }

    func testRateLimitedWithDateHeaderYieldsNilSeconds() async {
        let client = TestSupport.makeClient(status: 429, headers: ["Retry-After": "Wed, 21 Oct 2026 07:28:00 GMT"])
        let error = await TestSupport.capturedError { try await client.popularShows() }
        XCTAssertEqual(error, .rateLimited(retryAfter: nil))
    }

    func testOtherStatusUsesTMDBMessage() async {
        let body = Data("{\"success\":false,\"status_code\":11,\"status_message\":\"Internal error: Something went wrong, contact TMDB.\"}".utf8)
        let client = TestSupport.makeClient(status: 500, body: body)
        let error = await TestSupport.capturedError { try await client.trending() }
        XCTAssertEqual(error, .http(status: 500, message: "Internal error: Something went wrong, contact TMDB."))
        XCTAssertTrue(error?.errorDescription?.contains("500") == true)
    }

    func testOtherStatusWithoutBodyHasNilMessage() async {
        let client = TestSupport.makeClient(status: 503)
        let error = await TestSupport.capturedError { try await client.trending() }
        XCTAssertEqual(error, .http(status: 503, message: nil))
    }

    func testOtherStatusWithNonJSONBodyHasNilMessage() async {
        let client = TestSupport.makeClient(status: 502, body: Data("<html>Bad Gateway</html>".utf8))
        let error = await TestSupport.capturedError { try await client.trending() }
        XCTAssertEqual(error, .http(status: 502, message: nil))
    }

    // MARK: Transport and decoding failures

    func testURLErrorBecomesNetwork() async {
        let client = TMDBClient(credential: .bearer("a.b.c"), region: nil) { _ in
            throw URLError(.notConnectedToInternet)
        }
        let error = await TestSupport.capturedError { try await client.trending() }
        guard case .network(let message)? = error else {
            return XCTFail("Expected .network, got \(String(describing: error))")
        }
        XCTAssertFalse(message.isEmpty)
        XCTAssertNotNil(error?.errorDescription)
    }

    func testGarbageBodyBecomesDecoding() async {
        let client = TestSupport.makeClient(status: 200, body: Data("not json at all".utf8))
        let error = await TestSupport.capturedError { try await client.trending() }
        guard case .decoding? = error else {
            return XCTFail("Expected .decoding, got \(String(describing: error))")
        }
        XCTAssertNotNil(error?.errorDescription)
    }

    func testWrongShapeBecomesDecodingWithKeyPath() async throws {
        // A 200 whose body is a status envelope rather than a list: `results` is missing.
        let client = try TestSupport.makeClient(fixture: "error_401", status: 200)
        let error = await TestSupport.capturedError { try await client.popularMovies() }
        guard case .decoding(let detail)? = error else {
            return XCTFail("Expected .decoding, got \(String(describing: error))")
        }
        XCTAssertTrue(detail.contains("results"), detail)
    }

    func testMissingCredentials() async {
        let client = TestSupport.makeClient(credential: .bearer(""))
        let error = await TestSupport.capturedError { try await client.trending() }
        XCTAssertEqual(error, .missingCredentials)
    }

    // MARK: Success paths

    func testValidateCredentialsSuccess() async throws {
        let body = Data("{\"success\":true,\"status_code\":1,\"status_message\":\"Success.\"}".utf8)
        let client = TestSupport.makeClient(status: 200, body: body)
        let ok = try await client.validateCredentials()
        XCTAssertTrue(ok)
    }

    func testTwoHundredRangeIsAccepted() async throws {
        let client = try TestSupport.makeClient(fixture: "tv_airing_today", status: 203)
        let page = try await client.airingToday()
        XCTAssertEqual(page.results.count, 3)
    }

    // MARK: Descriptions and equality

    func testEveryErrorHasADescription() {
        let errors: [TMDBError] = [
            .missingCredentials,
            .unauthorized,
            .notFound,
            .rateLimited(retryAfter: nil),
            .rateLimited(retryAfter: 30),
            .http(status: 500, message: nil),
            .http(status: 500, message: "Boom"),
            .decoding(""),
            .decoding("Missing key"),
            .network(""),
            .network("Offline")
        ]
        for error in errors {
            XCTAssertFalse((error.errorDescription ?? "").isEmpty, "\(error)")
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error)")
        }
    }

    func testEquatable() {
        XCTAssertEqual(TMDBError.rateLimited(retryAfter: 3), TMDBError.rateLimited(retryAfter: 3))
        XCTAssertNotEqual(TMDBError.rateLimited(retryAfter: 3), TMDBError.rateLimited(retryAfter: nil))
        XCTAssertNotEqual(TMDBError.http(status: 500, message: nil), TMDBError.http(status: 502, message: nil))
        XCTAssertNotEqual(TMDBError.unauthorized, TMDBError.notFound)
    }

    // MARK: Static helpers

    func testRetryAfterHeaderIsCaseInsensitive() throws {
        let url = try XCTUnwrap(URL(string: "https://api.themoviedb.org/3/tv/1"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 429, httpVersion: "HTTP/1.1", headerFields: ["retry-after": " 12 "]))
        XCTAssertEqual(TMDBClient.retryAfterSeconds(from: response), 12)
    }

    func testStatusMessageHelper() throws {
        XCTAssertNil(TMDBClient.statusMessage(in: Data()))
        XCTAssertNil(TMDBClient.statusMessage(in: Data("{}".utf8)))
        XCTAssertEqual(
            TMDBClient.statusMessage(in: try TestSupport.fixtureData("error_401")),
            "Invalid API key: You must be granted a valid key."
        )
    }
}
