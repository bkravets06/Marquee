import Foundation

// MARK: - PagedResponse

/// One page of a TMDB list endpoint.
public struct PagedResponse<Item: Codable & Sendable>: Codable, Sendable {
    public var page: Int
    public var results: [Item]
    public var totalPages: Int
    public var totalResults: Int

    public init(page: Int, results: [Item], totalPages: Int, totalResults: Int) {
        self.page = page
        self.results = results
        self.totalPages = totalPages
        self.totalResults = totalResults
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case page
        case results
        case totalPages = "total_pages"
        case totalResults = "total_results"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        page = container.int(forKey: .page, fallback: 1)
        // `results` is the one field a list payload must carry; its absence means this is not a list.
        results = try container.decode([Item].self, forKey: .results)
        totalPages = container.int(forKey: .totalPages, fallback: 1)
        totalResults = container.int(forKey: .totalResults, fallback: 0)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(page, forKey: .page)
        try container.encode(results, forKey: .results)
        try container.encode(totalPages, forKey: .totalPages)
        try container.encode(totalResults, forKey: .totalResults)
    }

    // MARK: Mapping

    /// A page with the same paging metadata and transformed rows.
    public func map<Output: Codable & Sendable>(_ transform: (Item) -> Output) -> PagedResponse<Output> {
        PagedResponse<Output>(page: page, results: results.map(transform), totalPages: totalPages, totalResults: totalResults)
    }

    /// A page with the same paging metadata, keeping only rows for which `transform` returns a value.
    public func compactMap<Output: Codable & Sendable>(_ transform: (Item) -> Output?) -> PagedResponse<Output> {
        PagedResponse<Output>(page: page, results: results.compactMap(transform), totalPages: totalPages, totalResults: totalResults)
    }
}
