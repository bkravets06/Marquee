import Foundation

// MARK: - RawTVResult

/// A row from a TV list endpoint (`/tv/*`, `/search/tv`, `/trending/tv/*`).
struct RawTVResult: Codable, Sendable {
    var id: Int
    var name: String
    var overview: String
    var posterPath: String?
    var backdropPath: String?
    var firstAirDate: CivilDate?
    var voteAverage: Double
    var voteCount: Int
    var popularity: Double
    var genreIDs: [Int]
    var originalLanguage: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genreIDs = "genre_ids"
        case originalLanguage = "original_language"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = container.string(forKey: .name)
        overview = container.string(forKey: .overview)
        posterPath = container.optionalString(forKey: .posterPath)
        backdropPath = container.optionalString(forKey: .backdropPath)
        firstAirDate = container.civilDate(forKey: .firstAirDate)
        voteAverage = container.double(forKey: .voteAverage)
        voteCount = container.int(forKey: .voteCount)
        popularity = container.double(forKey: .popularity)
        genreIDs = try container.array(Int.self, forKey: .genreIDs)
        originalLanguage = container.optionalString(forKey: .originalLanguage)
    }

    var summary: MediaSummary {
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
            genreIDs: genreIDs,
            originalLanguage: originalLanguage
        )
    }
}

// MARK: - RawMovieResult

/// A row from a movie list endpoint (`/movie/*`, `/search/movie`, `/trending/movie/*`).
struct RawMovieResult: Codable, Sendable {
    var id: Int
    var title: String
    var overview: String
    var posterPath: String?
    var backdropPath: String?
    var releaseDate: CivilDate?
    var voteAverage: Double
    var voteCount: Int
    var popularity: Double
    var genreIDs: [Int]
    var originalLanguage: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genreIDs = "genre_ids"
        case originalLanguage = "original_language"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = container.string(forKey: .title)
        overview = container.string(forKey: .overview)
        posterPath = container.optionalString(forKey: .posterPath)
        backdropPath = container.optionalString(forKey: .backdropPath)
        releaseDate = container.civilDate(forKey: .releaseDate)
        voteAverage = container.double(forKey: .voteAverage)
        voteCount = container.int(forKey: .voteCount)
        popularity = container.double(forKey: .popularity)
        genreIDs = try container.array(Int.self, forKey: .genreIDs)
        originalLanguage = container.optionalString(forKey: .originalLanguage)
    }

    var summary: MediaSummary {
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
            genreIDs: genreIDs,
            originalLanguage: originalLanguage
        )
    }
}

// MARK: - RawMultiResult

/// A row from a mixed endpoint (`/trending/all/*`, `/search/multi`). Carries `media_type`;
/// person rows and unknown types have no `summary` and are dropped by the client.
struct RawMultiResult: Codable, Sendable {
    var id: Int
    var mediaType: String?
    var name: String?
    var title: String?
    var overview: String
    var posterPath: String?
    var backdropPath: String?
    var firstAirDate: CivilDate?
    var releaseDate: CivilDate?
    var voteAverage: Double
    var voteCount: Int
    var popularity: Double
    var genreIDs: [Int]
    var originalLanguage: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case mediaType = "media_type"
        case name
        case title
        case overview
        case posterPath = "poster_path"
        case backdropPath = "backdrop_path"
        case firstAirDate = "first_air_date"
        case releaseDate = "release_date"
        case voteAverage = "vote_average"
        case voteCount = "vote_count"
        case popularity
        case genreIDs = "genre_ids"
        case originalLanguage = "original_language"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        mediaType = container.optionalString(forKey: .mediaType)
        name = container.optionalString(forKey: .name)
        title = container.optionalString(forKey: .title)
        overview = container.string(forKey: .overview)
        posterPath = container.optionalString(forKey: .posterPath)
        backdropPath = container.optionalString(forKey: .backdropPath)
        firstAirDate = container.civilDate(forKey: .firstAirDate)
        releaseDate = container.civilDate(forKey: .releaseDate)
        voteAverage = container.double(forKey: .voteAverage)
        voteCount = container.int(forKey: .voteCount)
        popularity = container.double(forKey: .popularity)
        genreIDs = try container.array(Int.self, forKey: .genreIDs)
        originalLanguage = container.optionalString(forKey: .originalLanguage)
    }

    /// The kind this row maps to, or `nil` for people and unknown media types.
    var kind: MediaKind? {
        switch mediaType {
        case "tv": return .show
        case "movie": return .movie
        default: return nil
        }
    }

    var summary: MediaSummary? {
        guard let kind = kind else { return nil }
        let resolvedTitle: String
        let resolvedDate: CivilDate?
        switch kind {
        case .show:
            resolvedTitle = name ?? title ?? ""
            resolvedDate = firstAirDate ?? releaseDate
        case .movie:
            resolvedTitle = title ?? name ?? ""
            resolvedDate = releaseDate ?? firstAirDate
        }
        return MediaSummary(
            id: id,
            kind: kind,
            title: resolvedTitle,
            overview: overview,
            posterPath: posterPath,
            backdropPath: backdropPath,
            releaseDate: resolvedDate,
            voteAverage: voteAverage,
            voteCount: voteCount,
            popularity: popularity,
            genreIDs: genreIDs,
            originalLanguage: originalLanguage
        )
    }
}

// MARK: - TMDBStatusResponse

/// TMDB's generic status envelope, returned by `/authentication` and by error responses.
struct TMDBStatusResponse: Decodable, Sendable {
    var success: Bool?
    var statusCode: Int?
    var statusMessage: String?

    private enum CodingKeys: String, CodingKey {
        case success
        case statusCode = "status_code"
        case statusMessage = "status_message"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        success = try? container.decodeIfPresent(Bool.self, forKey: .success)
        statusCode = container.optionalInt(forKey: .statusCode)
        statusMessage = container.optionalString(forKey: .statusMessage)
    }
}
