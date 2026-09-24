import XCTest
import MarqueeKit
@testable import Marquee

// MARK: - DetailModelTests

/// Pure, network-free coverage of the Where to Watch state in `DetailModel`:
/// region lookup, which titles support it and the no-client short circuit.
@MainActor
final class DetailModelTests: XCTestCase {

    // MARK: Helpers

    private func tmdbShowModel() -> DetailModel {
        DetailModel(reference: .tmdb(id: 95396, kind: .show))
    }

    private func customShowModel() -> DetailModel {
        let model = DetailModel(reference: .library(UUID()))
        model.item = MediaItem(kind: .show, status: .watching, title: "Custom", isCustom: true)
        return model
    }

    private func assertWatchProvidersUntouched(_ model: DetailModel, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNil(model.watchProviders, file: file, line: line)
        XCTAssertFalse(model.isLoadingWatchProviders, file: file, line: line)
        XCTAssertNil(model.watchProvidersErrorMessage, file: file, line: line)
    }

    // MARK: Region lookup

    func testWatchProvidersRegionLookup() {
        let model = tmdbShowModel()
        XCTAssertNil(model.watchProviders(in: "US"))

        model.watchProviders = PreviewData.sampleWatchProviders

        XCTAssertEqual(model.watchProviders(in: "us")?.groups.map { $0.kind }, [.flatrate, .buy])
        XCTAssertNil(model.watchProviders(in: "FR"))
    }

    // MARK: Support

    func testSupportsWatchProvidersForTMDBAndCustomTitles() throws {
        XCTAssertTrue(tmdbShowModel().supportsWatchProviders)
        XCTAssertFalse(customShowModel().supportsWatchProviders)

        let libraryModel = DetailModel(reference: .library(UUID()))
        libraryModel.item = try XCTUnwrap(PreviewData.sampleItems().first { $0.tmdbID != nil && !$0.isCustom })
        XCTAssertTrue(libraryModel.supportsWatchProviders)
    }

    // MARK: Loading

    func testLoadWatchProvidersWithoutClientLeavesStateAlone() async {
        let model = tmdbShowModel()

        await model.loadWatchProviders(client: nil)

        assertWatchProvidersUntouched(model)
    }

    func testLoadWatchProvidersSkipsCustomTitles() async {
        let model = customShowModel()

        await model.loadWatchProviders(client: nil)

        assertWatchProvidersUntouched(model)
    }
}
