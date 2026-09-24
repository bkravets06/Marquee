import Foundation
import XCTest
@testable import MarqueeKit
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - RequestRecorder

/// Thread-safe recorder for the requests a stub transport receives.
final class RequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [URLRequest] = []

    func record(_ request: URLRequest) {
        lock.lock()
        storage.append(request)
        lock.unlock()
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    var last: URLRequest? { requests.last }
}

// MARK: - TestSupport

enum FixtureError: Error {
    case missing(String)
}

enum TestSupport {

    // MARK: Fixtures

    static func fixtureURL(_ name: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw FixtureError.missing(name)
        }
        return url
    }

    static func fixtureData(_ name: String) throws -> Data {
        try Data(contentsOf: fixtureURL(name))
    }

    // MARK: Calendars and dates

    /// Gregorian calendar pinned to Los Angeles with an en_US_POSIX locale, so date math is deterministic.
    static var losAngeles: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles") ?? TimeZone(secondsFromGMT: -7 * 3600)!
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return calendar
    }

    /// Thursday 2026-09-24 12:00 in Los Angeles.
    static let referenceNow = Date(timeIntervalSince1970: 1_790_276_400)

    // MARK: Clients

    /// A client whose transport answers every request with `status`, `headers` and `body`, recording requests.
    static func makeClient(
        credential: TMDBCredential = .bearer("eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ0ZXN0In0.c2lnbmF0dXJl"),
        language: String = "en-US",
        region: String? = "US",
        baseURL: URL = TMDBClient.baseURL,
        status: Int = 200,
        headers: [String: String] = [:],
        body: Data = Data(),
        recorder: RequestRecorder? = nil
    ) -> TMDBClient {
        TMDBClient(credential: credential, language: language, region: region, baseURL: baseURL) { request in
            recorder?.record(request)
            guard let url = request.url,
                  let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers) else {
                throw URLError(.badURL)
            }
            return (body, response)
        }
    }

    /// A client that answers every request with the named fixture and the given status.
    static func makeClient(
        fixture: String,
        status: Int = 200,
        headers: [String: String] = [:],
        credential: TMDBCredential = .bearer("eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ0ZXN0In0.c2lnbmF0dXJl"),
        region: String? = "US",
        recorder: RequestRecorder? = nil
    ) throws -> TMDBClient {
        let body = try fixtureData(fixture)
        return makeClient(credential: credential, region: region, status: status, headers: headers, body: body, recorder: recorder)
    }

    // MARK: Request inspection

    static func path(of request: URLRequest?) -> String {
        guard let url = request?.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return ""
        }
        return components.path
    }

    static func queryItems(of request: URLRequest?) -> [URLQueryItem] {
        guard let url = request?.url, let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return []
        }
        return components.queryItems ?? []
    }

    static func query(of request: URLRequest?) -> [String: String] {
        var result: [String: String] = [:]
        for item in queryItems(of: request) {
            result[item.name] = item.value ?? ""
        }
        return result
    }

    // MARK: Errors

    /// Runs `body` and returns the `TMDBError` it throws, failing the test if it succeeds or throws something else.
    static func capturedError<Value>(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ body: () async throws -> Value
    ) async -> TMDBError? {
        do {
            _ = try await body()
            XCTFail("Expected a TMDBError but the call succeeded", file: file, line: line)
            return nil
        } catch let error as TMDBError {
            return error
        } catch {
            XCTFail("Expected a TMDBError but got \(error)", file: file, line: line)
            return nil
        }
    }
}
