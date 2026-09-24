import Foundation

// MARK: - SeasonDetails

/// `GET /tv/{id}/season/{number}`.
public struct SeasonDetails: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var seasonNumber: Int
    public var name: String
    public var overview: String
    public var airDate: CivilDate?
    public var posterPath: String?
    public var episodes: [EpisodeSummary]

    public init(
        id: Int,
        seasonNumber: Int,
        name: String,
        overview: String,
        airDate: CivilDate? = nil,
        posterPath: String? = nil,
        episodes: [EpisodeSummary] = []
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.airDate = airDate
        self.posterPath = posterPath
        self.episodes = episodes
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case seasonNumber = "season_number"
        case name
        case overview
        case airDate = "air_date"
        case posterPath = "poster_path"
        case episodes
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        seasonNumber = container.int(forKey: .seasonNumber)
        name = container.string(forKey: .name)
        overview = container.string(forKey: .overview)
        airDate = container.civilDate(forKey: .airDate)
        posterPath = container.optionalString(forKey: .posterPath)
        episodes = try container.array(EpisodeSummary.self, forKey: .episodes)
    }
}
