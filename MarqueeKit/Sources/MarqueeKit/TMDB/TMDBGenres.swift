import Foundation

// MARK: - TMDBGenres

/// The official TMDB genre tables, so list rows (which only carry `genre_ids`) can show names offline.
public enum TMDBGenres {

    /// TV genres (`GET /genre/tv/list`).
    public static let tv: [Int: String] = [
        10759: "Action & Adventure",
        16: "Animation",
        35: "Comedy",
        80: "Crime",
        99: "Documentary",
        18: "Drama",
        10751: "Family",
        10762: "Kids",
        9648: "Mystery",
        10763: "News",
        10764: "Reality",
        10765: "Sci-Fi & Fantasy",
        10766: "Soap",
        10767: "Talk",
        10768: "War & Politics",
        37: "Western"
    ]

    /// Movie genres (`GET /genre/movie/list`).
    public static let movie: [Int: String] = [
        28: "Action",
        12: "Adventure",
        16: "Animation",
        35: "Comedy",
        80: "Crime",
        99: "Documentary",
        18: "Drama",
        10751: "Family",
        14: "Fantasy",
        36: "History",
        27: "Horror",
        10402: "Music",
        9648: "Mystery",
        10749: "Romance",
        878: "Science Fiction",
        10770: "TV Movie",
        53: "Thriller",
        10752: "War",
        37: "Western"
    ]

    /// The genre name for `id` in the table that belongs to `kind`.
    public static func name(for id: Int, kind: MediaKind) -> String? {
        switch kind {
        case .show: return tv[id]
        case .movie: return movie[id]
        }
    }

    /// The genre name for `id`, looking in the TV table first and then the movie table.
    public static func name(for id: Int) -> String? {
        tv[id] ?? movie[id]
    }
}
