import Foundation
import XCTest
@testable import MarqueeKit

final class TMDBCredentialTests: XCTestCase {

    private let token = "eyJhbGciOiJIUzI1NiJ9.eyJhdWQiOiJ0ZXN0IiwibmJmIjoxNzAwMDAwMDAwfQ.c2lnbmF0dXJl"
    private let apiKey = "0123456789abcdef0123456789ABCDEF"

    func testDetectsBearerTokenByDots() {
        XCTAssertEqual(TMDBCredential.detect(token), .bearer(token))
    }

    func testDetectsHexAPIKey() {
        XCTAssertEqual(TMDBCredential.detect(apiKey), .apiKey(apiKey))
    }

    func testTrimsWhitespace() {
        XCTAssertEqual(TMDBCredential.detect("  \(token)\n"), .bearer(token))
        XCTAssertEqual(TMDBCredential.detect("\t\(apiKey) "), .apiKey(apiKey))
    }

    func testEmptyIsNil() {
        XCTAssertNil(TMDBCredential.detect(""))
        XCTAssertNil(TMDBCredential.detect("   \n"))
    }

    func testStripsPastedBearerPrefix() {
        XCTAssertEqual(TMDBCredential.detect("Bearer \(token)"), .bearer(token))
        XCTAssertNil(TMDBCredential.detect("Bearer "))
    }

    func testUnknownShapesFallBackByLength() {
        let longOpaque = String(repeating: "a", count: 64)
        XCTAssertEqual(TMDBCredential.detect(longOpaque), .bearer(longOpaque))
        XCTAssertEqual(TMDBCredential.detect("short-key"), .apiKey("short-key"))
        let notHex = "0123456789abcdef0123456789abcdeg"
        XCTAssertEqual(TMDBCredential.detect(notHex), .apiKey(notHex))
    }

    func testValueAndUsability() {
        XCTAssertEqual(TMDBCredential.bearer(token).value, token)
        XCTAssertEqual(TMDBCredential.apiKey(apiKey).value, apiKey)
        XCTAssertTrue(TMDBCredential.apiKey(apiKey).isUsable)
        XCTAssertFalse(TMDBCredential.bearer("").isUsable)
    }
}
