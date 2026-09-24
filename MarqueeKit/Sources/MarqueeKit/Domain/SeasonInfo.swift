import Foundation

// MARK: - SeasonInfo

/// Compact, persistable description of one season of a show.
public struct SeasonInfo: Hashable, Codable, Sendable, Identifiable {
    public var number: Int
    public var name: String
    public var episodeCount: Int
    public var airDate: CivilDate?
    public var posterPath: String?

    public var id: Int { number }

    public init(number: Int, name: String, episodeCount: Int, airDate: CivilDate? = nil, posterPath: String? = nil) {
        self.number = number
        self.name = name
        self.episodeCount = episodeCount
        self.airDate = airDate
        self.posterPath = posterPath
    }
}
