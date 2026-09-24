import Foundation

// MARK: - WatchProvider

/// One streaming service, store or channel as TMDB lists it. The data comes
/// from JustWatch, which TMDB's terms require crediting wherever it is shown.
public struct WatchProvider: Hashable, Codable, Sendable, Identifiable {
    /// TMDB's `provider_id`.
    public var id: Int
    public var name: String
    /// Raw TMDB `logo_path` ("/abc.jpg"); provider logos are square.
    public var logoPath: String?
    /// TMDB's ordering hint for the region; lower values are listed first.
    public var displayPriority: Int

    public init(id: Int, name: String, logoPath: String? = nil, displayPriority: Int = 0) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
        self.displayPriority = displayPriority
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id = "provider_id"
        case name = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = container.string(forKey: .name)
        logoPath = container.optionalString(forKey: .logoPath)
        displayPriority = container.int(forKey: .displayPriority)
    }
}

// MARK: - WatchOfferKind

/// How a title is offered. Raw values are TMDB's keys; `allCases` is the display order.
public enum WatchOfferKind: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Included with a subscription.
    case flatrate
    case free
    case ads
    case rent
    case buy

    public var id: String { rawValue }

    /// "Stream", "Free", "Free with Ads", "Rent" or "Buy".
    public var displayName: String {
        switch self {
        case .flatrate: return "Stream"
        case .free: return "Free"
        case .ads: return "Free with Ads"
        case .rent: return "Rent"
        case .buy: return "Buy"
        }
    }
}

// MARK: - WatchOfferGroup

/// The providers offering a title one way, ready to display.
public struct WatchOfferGroup: Hashable, Sendable, Identifiable {
    public var kind: WatchOfferKind
    public var providers: [WatchProvider]

    public var id: WatchOfferKind { kind }

    public init(kind: WatchOfferKind, providers: [WatchProvider]) {
        self.kind = kind
        self.providers = providers
    }
}

// MARK: - RegionWatchProviders

/// Everything TMDB lists for one title in one region.
public struct RegionWatchProviders: Hashable, Codable, Sendable {
    /// ISO 3166-1 alpha-2 code, uppercased.
    public var region: String
    /// TMDB's watch page for the title in this region. It carries the JustWatch
    /// attribution, so it is the link to offer when showing provider data.
    public var link: URL?
    public var flatrate: [WatchProvider]
    public var free: [WatchProvider]
    public var ads: [WatchProvider]
    public var rent: [WatchProvider]
    public var buy: [WatchProvider]

    public init(
        region: String,
        link: URL? = nil,
        flatrate: [WatchProvider] = [],
        free: [WatchProvider] = [],
        ads: [WatchProvider] = [],
        rent: [WatchProvider] = [],
        buy: [WatchProvider] = []
    ) {
        self.region = region
        self.link = link
        self.flatrate = flatrate
        self.free = free
        self.ads = ads
        self.rent = rent
        self.buy = buy
    }

    // MARK: Derived values

    /// The providers listed under `kind`, in TMDB's order.
    public func providers(of kind: WatchOfferKind) -> [WatchProvider] {
        switch kind {
        case .flatrate: return flatrate
        case .free: return free
        case .ads: return ads
        case .rent: return rent
        case .buy: return buy
        }
    }

    /// Non-empty kinds in `WatchOfferKind.allCases` order. Each group is sorted
    /// by display priority, then name, with repeated provider ids dropped.
    public var groups: [WatchOfferGroup] {
        WatchOfferKind.allCases.compactMap { kind in
            let providers = RegionWatchProviders.ordered(self.providers(of: kind))
            guard !providers.isEmpty else { return nil }
            return WatchOfferGroup(kind: kind, providers: providers)
        }
    }

    /// `true` when no provider is listed under any kind.
    public var isEmpty: Bool {
        WatchOfferKind.allCases.allSatisfy { providers(of: $0).isEmpty }
    }

    /// An absolute web URL, or `nil`. Foundation percent-encodes almost any
    /// string into a `URL`, so a scheme and host are required as well.
    private static func webURL(from string: String?) -> URL? {
        guard let string, let url = URL(string: string), url.scheme != nil, url.host != nil else {
            return nil
        }
        return url
    }

    private static func ordered(_ providers: [WatchProvider]) -> [WatchProvider] {
        var seen = Set<Int>()
        return providers
            .sorted { lhs, rhs in
                if lhs.displayPriority != rhs.displayPriority {
                    return lhs.displayPriority < rhs.displayPriority
                }
                return lhs.name.localizedCompare(rhs.name) == .orderedAscending
            }
            .filter { seen.insert($0.id).inserted }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case region
        case link
        case flatrate
        case free
        case ads
        case rent
        case buy
    }

    /// TMDB nests these objects under their region code, so `region` is normally
    /// absent here and filled in by `WatchProviders`; a missing `link` becomes `nil`.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        region = container.string(forKey: .region).uppercased()
        link = RegionWatchProviders.webURL(from: container.optionalString(forKey: .link))
        flatrate = try container.array(WatchProvider.self, forKey: .flatrate)
        free = try container.array(WatchProvider.self, forKey: .free)
        ads = try container.array(WatchProvider.self, forKey: .ads)
        rent = try container.array(WatchProvider.self, forKey: .rent)
        buy = try container.array(WatchProvider.self, forKey: .buy)
    }
}

// MARK: - WatchProviders

/// `GET /tv/{id}/watch/providers` and `GET /movie/{id}/watch/providers`: where a
/// title can be streamed, rented or bought, per region.
public struct WatchProviders: Hashable, Codable, Sendable, Identifiable {
    /// The show or movie id the offers belong to.
    public var id: Int
    /// Offers keyed by uppercased region code. Regions TMDB lists without any
    /// provider are kept as they arrive; use `providers(in:)` to skip them.
    public var regions: [String: RegionWatchProviders]

    public init(id: Int, regions: [String: RegionWatchProviders]) {
        self.id = id
        self.regions = WatchProviders.normalized(regions)
    }

    // MARK: Lookup

    /// The offers for `region` (any case, surrounding whitespace ignored), or
    /// `nil` when TMDB lists no provider there.
    public func providers(in region: String) -> RegionWatchProviders? {
        let code = region.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let entry = regions[code], !entry.isEmpty else { return nil }
        return entry
    }

    /// Region codes with at least one provider, sorted.
    public var availableRegions: [String] {
        regions.filter { !$0.value.isEmpty }.keys.sorted()
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case regions = "results"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        regions = WatchProviders.normalized(try WatchProviders.decodeRegions(from: container))
    }

    /// `results` is an object keyed by region code. It is `[:]` when missing or
    /// null, and TMDB sends an empty array instead of an empty object for titles
    /// with no offers anywhere; anything else malformed still throws.
    private static func decodeRegions(from container: KeyedDecodingContainer<CodingKeys>) throws -> [String: RegionWatchProviders] {
        do {
            return try container.decodeIfPresent([String: RegionWatchProviders].self, forKey: .regions) ?? [:]
        } catch let error as DecodingError {
            guard case .typeMismatch = error else { throw error }
            let list = try container.nestedUnkeyedContainer(forKey: .regions)
            guard list.isAtEnd else { throw error }
            return [:]
        }
    }

    /// Uppercases the keys and stamps each entry with its key. When two keys
    /// collide after uppercasing, the first in sorted order wins.
    private static func normalized(_ raw: [String: RegionWatchProviders]) -> [String: RegionWatchProviders] {
        var result: [String: RegionWatchProviders] = [:]
        for key in raw.keys.sorted() {
            guard var entry = raw[key] else { continue }
            let code = key.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !code.isEmpty, result[code] == nil else { continue }
            entry.region = code
            result[code] = entry
        }
        return result
    }
}
