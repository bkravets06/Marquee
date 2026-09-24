import Foundation

// MARK: - MediaSummary

/// A list row for a show or movie, normalized from TMDB's tv/movie/multi result shapes.
public struct MediaSummary: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var kind: MediaKind
    public var title: String
    public var overview: String
    public var posterPath: String?
    public var backdropPath: String?
    /// `first_air_date` for shows, `release_date` for movies.
    public var releaseDate: CivilDate?
    public var voteAverage: Double
    public var voteCount: Int
    public var popularity: Double
    public var genreIDs: [Int]
    public var originalLanguage: String?

    public init(
        id: Int,
        kind: MediaKind,
        title: String,
        overview: String,
        posterPath: String?,
        backdropPath: String?,
        releaseDate: CivilDate?,
        voteAverage: Double,
        voteCount: Int,
        popularity: Double,
        genreIDs: [Int],
        originalLanguage: String?
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.overview = overview
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.releaseDate = releaseDate
        self.voteAverage = voteAverage
        self.voteCount = voteCount
        self.popularity = popularity
        self.genreIDs = genreIDs
        self.originalLanguage = originalLanguage
    }

    // MARK: Derived values

    /// Stable identity across kinds ("show-123"); use it for `ForEach` ids in mixed lists.
    public var key: String { "\(kind.rawValue)-\(id)" }

    /// Release year, when a release date is known.
    public var year: Int? { releaseDate?.year }

    /// Genre names via `TMDBGenres`, in the order TMDB listed them; unknown ids are dropped.
    public var genreNames: [String] {
        genreIDs.compactMap { id in
            TMDBGenres.name(for: id, kind: kind) ?? TMDBGenres.name(for: id)
        }
    }
}
