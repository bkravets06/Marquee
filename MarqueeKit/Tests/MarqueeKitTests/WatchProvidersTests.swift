import Foundation
import XCTest
@testable import MarqueeKit

/// Decoding, lookup and grouping of watch provider data.
final class WatchProvidersTests: XCTestCase {

    // MARK: Fixtures

    func testMovieWatchProvidersDecodeAndGroup() async throws {
        let client = try TestSupport.makeClient(fixture: "movie_watch_providers")
        let providers = try await client.watchProviders(id: 693134, kind: .movie)

        XCTAssertEqual(providers.id, 693134)
        XCTAssertEqual(Set(providers.regions.keys), ["CA", "GB", "JP", "US"])
        XCTAssertEqual(providers.availableRegions, ["CA", "GB", "US"], "JP only carries a link")

        let us = try XCTUnwrap(providers.providers(in: "US"))
        XCTAssertEqual(us.region, "US")
        XCTAssertEqual(us.link?.absoluteString, "https://www.themoviedb.org/movie/693134-dune-part-two/watch?locale=US")
        XCTAssertEqual(us.flatrate.map { $0.name }, ["Max", "Max Amazon Channel"])
        XCTAssertEqual(us.rent.count, 6)
        XCTAssertEqual(us.buy.count, 5)
        XCTAssertEqual(us.free, [])
        XCTAssertEqual(us.ads, [])

        let groups = us.groups
        XCTAssertEqual(groups.map { $0.kind }, [.flatrate, .rent, .buy])
        XCTAssertEqual(groups[0].providers.map { $0.id }, [1899, 1825])
        XCTAssertEqual(groups[1].providers.map { $0.name }, [
            "Apple TV", "Amazon Video", "Google Play Movies", "YouTube", "Fandango At Home", "Spectrum On Demand"
        ], "rent is re-sorted by display priority")
        XCTAssertEqual(groups[2].providers.map { $0.displayPriority }, [5, 7, 10, 14, 16])

        let spectrum = try XCTUnwrap(us.rent.first { $0.id == 486 })
        XCTAssertNil(spectrum.logoPath, "a null logo_path decodes as nil")
        XCTAssertEqual(spectrum.displayPriority, 141)
        XCTAssertEqual(us.flatrate[0].logoPath, "/jbe4gVSfRlbPTdESXhEKpornsfu.jpg")
    }

    func testTVWatchProvidersDecode() async throws {
        let client = try TestSupport.makeClient(fixture: "tv_watch_providers")
        let providers = try await client.watchProviders(id: 95396, kind: .show)

        XCTAssertEqual(providers.id, 95396)
        XCTAssertEqual(providers.availableRegions, ["AU", "GB", "US"])

        let us = try XCTUnwrap(providers.providers(in: "US"))
        XCTAssertEqual(us.groups.map { $0.kind }, [.flatrate, .buy])
        XCTAssertEqual(us.groups[0].providers.map { $0.name }, ["Apple TV+", "Apple TV+ Amazon Channel"])
        XCTAssertEqual(us.groups[1].providers.map { $0.id }, [2])

        let au = try XCTUnwrap(providers.providers(in: "AU"))
        XCTAssertEqual(au.groups.count, 1, "empty free and ads arrays produce no groups")
        XCTAssertEqual(au.providers(of: .free), [])
        XCTAssertEqual(au.providers(of: .ads), [])
    }

    // MARK: Lookup

    func testRegionLookupIsCaseAndWhitespaceInsensitive() async throws {
        let client = try TestSupport.makeClient(fixture: "movie_watch_providers")
        let providers = try await client.watchProviders(id: 693134, kind: .movie)

        XCTAssertNotNil(providers.providers(in: "us"))
        XCTAssertNotNil(providers.providers(in: " gb "))
        XCTAssertEqual(providers.providers(in: "ca")?.region, "CA")
        XCTAssertNil(providers.providers(in: "JP"), "a region with only a link has nothing to show")
        XCTAssertNil(providers.providers(in: "FR"))
        XCTAssertNil(providers.providers(in: ""))
    }

    func testKeysAreNormalizedAndStamped() {
        let entry = RegionWatchProviders(region: "", flatrate: [WatchProvider(id: 8, name: "Netflix")])
        let providers = WatchProviders(id: 1, regions: ["us": entry, " De ": entry])
        XCTAssertEqual(Set(providers.regions.keys), ["US", "DE"])
        XCTAssertEqual(providers.regions["US"]?.region, "US")
        XCTAssertEqual(providers.regions["DE"]?.region, "DE")
        XCTAssertEqual(providers.availableRegions, ["DE", "US"])
    }

    // MARK: Grouping

    func testGroupsFollowDisplayOrderSortAndDeduplicate() {
        let netflix = WatchProvider(id: 8, name: "Netflix", logoPath: "/n.jpg", displayPriority: 0)
        let hulu = WatchProvider(id: 15, name: "Hulu", logoPath: "/h.jpg", displayPriority: 4)
        let peacock = WatchProvider(id: 386, name: "Peacock", displayPriority: 4)
        let tubi = WatchProvider(id: 73, name: "Tubi TV", displayPriority: 22)
        let apple = WatchProvider(id: 2, name: "Apple TV", displayPriority: 5)

        let region = RegionWatchProviders(
            region: "US",
            flatrate: [peacock, hulu, netflix, hulu],
            free: [tubi],
            ads: [peacock],
            rent: [],
            buy: [apple]
        )

        let groups = region.groups
        XCTAssertEqual(groups.map { $0.kind }, [.flatrate, .free, .ads, .buy])
        XCTAssertEqual(groups.map { $0.id }, groups.map { $0.kind })
        XCTAssertEqual(groups[0].providers.map { $0.name }, ["Netflix", "Hulu", "Peacock"], "priority first, then name; the repeated Hulu is dropped")
        XCTAssertEqual(groups[1].providers, [tubi])
        XCTAssertEqual(groups[2].providers, [peacock])
        XCTAssertEqual(groups[3].providers, [apple])
        XCTAssertFalse(region.isEmpty)
    }

    func testEmptyRegion() {
        let region = RegionWatchProviders(region: "US", link: URL(string: "https://example.com/watch"))
        XCTAssertTrue(region.isEmpty)
        XCTAssertEqual(region.groups, [])
        let providers = WatchProviders(id: 1, regions: ["US": region])
        XCTAssertNil(providers.providers(in: "US"))
        XCTAssertEqual(providers.availableRegions, [])
        XCTAssertEqual(providers.regions.count, 1, "the raw entry is kept")
    }

    func testOfferKindDisplayNamesAndOrder() {
        XCTAssertEqual(WatchOfferKind.allCases, [.flatrate, .free, .ads, .rent, .buy])
        XCTAssertEqual(WatchOfferKind.allCases.map { $0.displayName }, ["Stream", "Free", "Free with Ads", "Rent", "Buy"])
        XCTAssertEqual(WatchOfferKind.flatrate.id, "flatrate")
        XCTAssertEqual(WatchOfferKind(rawValue: "ads"), .ads)
    }

    // MARK: Leniency

    func testMissingResultsBecomesNoRegions() throws {
        let providers = try JSONDecoder().decode(WatchProviders.self, from: Data("{\"id\": 7}".utf8))
        XCTAssertEqual(providers.id, 7)
        XCTAssertEqual(providers.regions, [:])
        XCTAssertNil(providers.providers(in: "US"))

        let null = try JSONDecoder().decode(WatchProviders.self, from: Data("{\"id\": 7, \"results\": null}".utf8))
        XCTAssertEqual(null.regions, [:])
    }

    func testEmptyResultsArrayIsTolerated() throws {
        let providers = try JSONDecoder().decode(WatchProviders.self, from: Data("{\"id\": 7, \"results\": []}".utf8))
        XCTAssertEqual(providers.regions, [:])
    }

    func testMalformedResultsStillThrow() {
        XCTAssertThrowsError(try JSONDecoder().decode(WatchProviders.self, from: Data("{\"id\": 7, \"results\": \"none\"}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(WatchProviders.self, from: Data("{\"id\": 7, \"results\": [1]}".utf8)))
        XCTAssertThrowsError(try JSONDecoder().decode(WatchProviders.self, from: Data("{\"results\": {}}".utf8)), "id is required")
        XCTAssertThrowsError(try JSONDecoder().decode(WatchProvider.self, from: Data("{\"provider_name\": \"No id\"}".utf8)))
        let badProvider = "{\"id\": 7, \"results\": {\"US\": {\"flatrate\": [{\"provider_name\": \"No id\"}]}}}"
        XCTAssertThrowsError(try JSONDecoder().decode(WatchProviders.self, from: Data(badProvider.utf8)))
    }

    func testSparseRegionAndProviderFallBackToDefaults() throws {
        let json = "{\"id\": 7, \"results\": {\"us\": {\"link\": \"\", \"flatrate\": [{\"provider_id\": 8}], \"rent\": null}}}"
        let providers = try JSONDecoder().decode(WatchProviders.self, from: Data(json.utf8))
        let us = try XCTUnwrap(providers.providers(in: "US"))
        XCTAssertEqual(us.region, "US", "the lowercase key is uppercased and stamped onto the entry")
        XCTAssertNil(us.link, "an empty link becomes nil")
        XCTAssertEqual(us.rent, [])
        let provider = try XCTUnwrap(us.flatrate.first)
        XCTAssertEqual(provider.id, 8)
        XCTAssertEqual(provider.name, "")
        XCTAssertNil(provider.logoPath)
        XCTAssertEqual(provider.displayPriority, 0)
    }

    func testInvalidLinkBecomesNil() throws {
        let json = "{\"id\": 7, \"results\": {\"US\": {\"link\": \"not a url\", \"buy\": [{\"provider_id\": 2, \"provider_name\": \"Apple TV\"}]}}}"
        let providers = try JSONDecoder().decode(WatchProviders.self, from: Data(json.utf8))
        XCTAssertNil(providers.providers(in: "US")?.link)
    }

    // MARK: Round trips

    func testWatchProvidersSurviveEncodeDecodeRoundTrip() async throws {
        let client = try TestSupport.makeClient(fixture: "movie_watch_providers")
        let providers = try await client.watchProviders(id: 693134, kind: .movie)
        let data = try JSONEncoder().encode(providers)
        let decoded = try JSONDecoder().decode(WatchProviders.self, from: data)
        XCTAssertEqual(decoded, providers)
        XCTAssertEqual(decoded.providers(in: "US")?.groups, providers.providers(in: "US")?.groups)
    }

    func testProviderEncodesWithTMDBKeys() throws {
        let provider = WatchProvider(id: 8, name: "Netflix", logoPath: "/n.jpg", displayPriority: 1)
        let data = try JSONEncoder().encode(provider)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["provider_id"] as? Int, 8)
        XCTAssertEqual(object["provider_name"] as? String, "Netflix")
        XCTAssertEqual(object["logo_path"] as? String, "/n.jpg")
        XCTAssertEqual(object["display_priority"] as? Int, 1)
        XCTAssertEqual(try JSONDecoder().decode(WatchProvider.self, from: data), provider)
    }
}
