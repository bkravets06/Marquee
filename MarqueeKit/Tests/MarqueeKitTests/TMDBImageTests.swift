import Foundation
import XCTest
@testable import MarqueeKit

final class TMDBImageTests: XCTestCase {

    func testPosterURL() {
        XCTAssertEqual(TMDBImage.poster("/abc.jpg")?.absoluteString, "https://image.tmdb.org/t/p/w342/abc.jpg")
        XCTAssertEqual(TMDBImage.poster("/abc.jpg", size: .w500)?.absoluteString, "https://image.tmdb.org/t/p/w500/abc.jpg")
        XCTAssertEqual(TMDBImage.poster("/abc.jpg", size: .original)?.absoluteString, "https://image.tmdb.org/t/p/original/abc.jpg")
    }

    func testBackdropURL() {
        XCTAssertEqual(TMDBImage.backdrop("/wide.jpg")?.absoluteString, "https://image.tmdb.org/t/p/w780/wide.jpg")
        XCTAssertEqual(TMDBImage.backdrop("/wide.jpg", size: .w1280)?.absoluteString, "https://image.tmdb.org/t/p/w1280/wide.jpg")
    }

    func testStillURL() {
        XCTAssertEqual(TMDBImage.still("/still.jpg")?.absoluteString, "https://image.tmdb.org/t/p/w300/still.jpg")
        XCTAssertEqual(TMDBImage.still("/still.jpg", size: .w185)?.absoluteString, "https://image.tmdb.org/t/p/w185/still.jpg")
    }

    func testGenericBuilder() {
        XCTAssertEqual(TMDBImage.url(path: "/x.png", size: "w92")?.absoluteString, "https://image.tmdb.org/t/p/w92/x.png")
        XCTAssertEqual(TMDBImage.url(path: "x.png", size: "w92")?.absoluteString, "https://image.tmdb.org/t/p/w92/x.png", "a missing leading slash is tolerated")
    }

    func testMissingOrEmptyPathIsNil() {
        XCTAssertNil(TMDBImage.poster(nil))
        XCTAssertNil(TMDBImage.poster(""))
        XCTAssertNil(TMDBImage.poster("   "))
        XCTAssertNil(TMDBImage.poster("/"))
        XCTAssertNil(TMDBImage.backdrop(nil))
        XCTAssertNil(TMDBImage.still(nil))
    }

    func testBaseURL() {
        XCTAssertEqual(TMDBImage.baseURL.absoluteString, "https://image.tmdb.org/t/p/")
        XCTAssertEqual(TMDBClient.baseURL.absoluteString, "https://api.themoviedb.org/3")
    }
}
