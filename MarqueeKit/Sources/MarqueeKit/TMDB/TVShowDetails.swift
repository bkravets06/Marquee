import Foundation

// MARK: - Genre

public struct Genre: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = container.string(forKey: .name)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
    }
}

// MARK: - Network

public struct Network: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var logoPath: String?

    public init(id: Int, name: String, logoPath: String? = nil) {
        self.id = id
        self.name = name
        self.logoPath = logoPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = container.string(forKey: .name)
        logoPath = container.optionalString(forKey: .logoPath)
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case logoPath = "logo_path"
    }
}

// MARK: - EpisodeSummary

/// One episode, as returned inside season details and `next_episode_to_air` / `last_episode_to_air`.
public struct EpisodeSummary: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var overview: String
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var airDate: CivilDate?
    public var stillPath: String?
    public var runtime: Int?
    public var voteAverage: Double?

    public init(
        id: Int,
        name: String,
        overview: String,
        seasonNumber: Int,
        episodeNumber: Int,
        airDate: CivilDate? = nil,
        stillPath: String? = nil,
        runtime: Int? = nil,
        voteAverage: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.seasonNumber = seasonNumber
        self.episodeNumber = episodeNumber
        self.airDate = airDate
        self.stillPath = stillPath
        self.runtime = runtime
        self.voteAverage = voteAverage
    }

    /// The episode's position as a progress pointer.
    public var pointer: EpisodePointer {
        EpisodePointer(season: seasonNumber, episode: episodeNumber)
    }

    /// `true` when an air date is known and it is on or before `today`.
    public func hasAired(asOf today: CivilDate) -> Bool {
        guard let airDate = airDate else { return false }
        return airDate <= today
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case seasonNumber = "season_number"
        case episodeNumber = "episode_number"
        case airDate = "air_date"
        case stillPath = "still_path"
        case runtime
        case voteAverage = "vote_average"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = container.string(forKey: .name)
        overview = container.string(forKey: .overview)
        seasonNumber = container.int(forKey: .seasonNumber)
        episodeNumber = container.int(forKey: .episodeNumber)
        airDate = container.civilDate(forKey: .airDate)
        stillPath = container.optionalString(forKey: .stillPath)
        runtime = container.optionalInt(forKey: .runtime)
        voteAverage = container.optionalDouble(forKey: .voteAverage)
    }
}

// MARK: - TVSeasonSummary

/// A season entry inside show details.
public struct TVSeasonSummary: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var seasonNumber: Int
    public var name: String
    public var overview: String
    public var episodeCount: Int
    public var airDate: CivilDate?
    public var posterPath: String?

    public init(
        id: Int,
        seasonNumber: Int,
        name: String,
        overview: String,
        episodeCount: Int,
        airDate: CivilDate? = nil,
        posterPath: String? = nil
    ) {
        self.id = id
        self.seasonNumber = seasonNumber
        self.name = name
        self.overview = overview
        self.episodeCount = episodeCount
        self.airDate = airDate
        self.posterPath = posterPath
    }

    /// The persistable form used by the app's library.
    public var info: SeasonInfo {
        SeasonInfo(number: seasonNumber, name: name, episodeCount: episodeCount, airDate: airDate, posterPath: posterPath)
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case seasonNumber = "season_number"
        case name
        case overview
        case episodeCount = "episode_count"
        case airDate = "air_date"
        case posterPath = "poster_path"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        seasonNumber = container.int(forKey: .seasonNumber)
        name = container.string(forKey: .name)
        overview = container.string(forKey: .overview)
        episodeCount = container.int(forKey: .episodeCount)
        airDate = container.civilDate(forKey: .airDate)
        posterPath = container.optionalString(forKey: .posterPath)
    }
}

// MARK: - TVShowDetails

/// `GET /tv/{id}`.
public struct TVShowDetails: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var overview: String
    public var tagline: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var firstAirDate: CivilDate?
    public var lastAirDate: CivilDate?
    public var genres: [Genre]
    /// "Returning Series", "Ended", "Canceled", "In Production", ...
    public var status: String?
    /// "Scripted", "Reality", ...
    public var type: String?
    public var numberOfSeasons: Int
    public var numberOfEpisodes: Int
    public var episodeRunTime: [Int]
    public var seasons: [TVSeasonSummary]
    public var nextEpisodeToAir: EpisodeSummary?
    public var lastEpisodeToAir: EpisodeSummary?
    public var networks: [Network]
    public var voteAverage: Double
    public var voteCount: Int
    public var inProduction: Bool
    public var homepage: String?
    public var originalLanguage: String?
    public var popularity: Double

    public init(
        id: Int,
        name: String,
        overview: String,
        tagline: String? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        firstAirDate: CivilDate? = nil,
        lastAirDate: CivilDate? = nil,
        genres: [Genre] = [],
        status: String? = nil,
        type: String? = nil,
        numberOfSeasons: Int = 0,
        numberOfEpisodes: Int = 0,
        episodeRunTime: [Int] = [],
        seasons: [TVSeasonSummary] = [],
        nextEpisodeToAir: EpisodeSummary? = nil,
        lastEpisodeToAir: EpisodeSummary? = nil,
        networks: [Network] = [],
        voteAverage: Double = 0,
        voteCount: Int = 0,
        inProduction: Bool = false,
        homepage: String? = nil,
        originalLanguage: String? = nil,
        popularity: Double = 0
    ) {
        self.id = id
        self.name = name
        self.overview = overview
        self.tagline = tagline
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.firstAirDate = firstAirDate
        self.lastAirDate = lastAirDate
        self.genres = genres
        self.status = status
        self.type = type
        self.numberOfSeasons = numberOfSeasons
        self.numberOfEpisodes = numberOfEpisodes
        self.episodeRunTime = episodeRunTime
        self.seasons = seasons
        self.nextEpisodeToAir = nextEpisodeToAir
        self.lastEpisodeToAir = lastEpisodeToAir
        self.networks = networks
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.inProduction = inProduction
        self.homepage = homepage
        self.originalLanguage = originalLanguage
        self.popularity = popularity
    }

    // MARK: Derived values

    /// The list-row form of this show.
    public var summary: MediaSummary {
        MediaSummary(
            id: id,
            kind: .show,
            title: name,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: firstAirDate,
            voteAverage: voteAverage,
            voteCount: voteCount,
            popularity: popularity,
            genreIDs: genres.map { $0.id },
            originalLanguage: originalLanguage
        )
    }

    /// Regular seasons (number >= 1) sorted ascending; specials are excluded.
    public var seasonInfos: [SeasonInfo] {
        seasons
            .filter { $0.seasonNumber >= 1 }
            .sorted { $0.seasonNumber < $1.seasonNumber }
            .map { $0.info }
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case tagline
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case lastAirDate = "last_air_date"
        case genres
        case status
        case type
        case numberOfSeasons = "number_of_seasons"
        case numberOfEpisodes = "number_of_episodes"
        case episodeRunTime = "episode_run_time"
        case seasons
        case nextEpisodeToAir = "next_episode_to_air"
        case lastEpisodeToAir = "last_episode_to_air"
        case networks
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case inProduction = "in_production"
        case homepage
        case originalLanguage = "original_language"
        case popularity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = container.string(forKey: .name)
        overview = container.string(forKey: .overview)
        tagline = container.optionalString(forKey: .tagline)
        posterPath = container.optionalString(forKey: .posterPath)
        backdropPath = container.optionalString(forKey: .backdropPath)
        firstAirDate = container.civilDate(forKey: .firstAirDate)
        lastAirDate = container.civilDate(forKey: .lastAirDate)
        genres = try container.array(Genre.self, forKey: .genres)
        status = container.optionalString(forKey: .status)
        type = container.optionalString(forKey: .type)
        numberOfSeasons = container.int(forKey: .numberOfSeasons)
        numberOfEpisodes = container.int(forKey: .numberOfEpisodes)
        episodeRunTime = try container.array(Int.self, forKey: .episodeRunTime)
        seasons = try container.array(TVSeasonSummary.self, forKey: .seasons)
        nextEpisodeToAir = try container.decodeIfPresent(EpisodeSummary.self, forKey: .nextEpisodeToAir)
        lastEpisodeToAir = try container.decodeIfPresent(EpisodeSummary.self, forKey: .lastEpisodeToAir)
        networks = try container.array(Network.self, forKey: .networks)
        voteAverage = container.double(forKey: .voteAverage)
        voteCount = container.int(forKey: .voteCount)
        inProduction = container.bool(forKey: .inProduction)
        homepage = container.optionalString(forKey: .homepage)
        originalLanguage = container.optionalString(forKey: .originalLanguage)
        popularity = container.double(forKey: .popularity)
    }
}
