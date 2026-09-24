import Foundation

// MARK: - MovieDetails

/// `GET /movie/{id}`.
public struct MovieDetails: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var overview: String
    public var tagline: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var releaseDate: CivilDate?
    public var runtime: Int?
    public var genres: [Genre]
    /// "Released", "Post Production", ...
    public var status: String?
    public var voteAverage: Double
    public var voteCount: Int
    public var homepage: String?
    public var originalLanguage: String?
    public var imdbID: String?
    public var popularity: Double

    public init(
        id: Int,
        title: String,
        overview: String,
        tagline: String? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        releaseDate: CivilDate? = nil,
        runtime: Int? = nil,
        genres: [Genre] = [],
        status: String? = nil,
        voteAverage: Double = 0,
        voteCount: Int = 0,
        homepage: String? = nil,
        originalLanguage: String? = nil,
        imdbID: String? = nil,
        popularity: Double = 0
    ) {
        self.id = id
        self.title = title
        self.overview = overview
        self.tagline = tagline
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseDate = releaseDate
        self.runtime = runtime
        self.genres = genres
        self.status = status
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.homepage = homepage
        self.originalLanguage = originalLanguage
        self.imdbID = imdbID
        self.popularity = popularity
    }

    // MARK: Derived values

    /// The list-row form of this movie.
    public var summary: MediaSummary {
        MediaSummary(
            id: id,
            kind: .movie,
            title: title,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: releaseDate,
            voteAverage: voteAverage,
            voteCount: voteCount,
            popularity: popularity,
            genreIDs: genres.map { $0.id },
            originalLanguage: originalLanguage
        )
    }

    // MARK: Codable

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case overview
        case tagline
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case runtime
        case genres
        case status
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case homepage
        case originalLanguage = "original_language"
        case imdbID = "imdb_id"
        case popularity
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = container.string(forKey: .title)
        overview = container.string(forKey: .overview)
        tagline = container.optionalString(forKey: .tagline)
        posterPath = container.optionalString(forKey: .posterPath)
        backdropPath = container.optionalString(forKey: .backdropPath)
        releaseDate = container.civilDate(forKey: .releaseDate)
        runtime = container.optionalInt(forKey: .runtime)
        genres = try container.array(Genre.self, forKey: .genres)
        status = container.optionalString(forKey: .status)
        voteAverage = container.double(forKey: .voteAverage)
        voteCount = container.int(forKey: .voteCount)
        homepage = container.optionalString(forKey: .homepage)
        originalLanguage = container.optionalString(forKey: .originalLanguage)
        imdbID = container.optionalString(forKey: .imdbID)
        popularity = container.double(forKey: .popularity)
    }
}
