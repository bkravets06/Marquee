import Foundation

// MARK: - TMDBEndpoint

/// A TMDB v3 endpoint: a path relative to the API base plus its query items.
/// `TMDBClient.makeRequest(_:)` adds language and credentials.
struct TMDBEndpoint: Hashable, Sendable {
    /// Path beginning with "/", e.g. "/tv/1399".
    var path: String
    /// Endpoint-specific query items (page, region, query, ...).
    var queryItems: [URLQueryItem]

    init(path: String, queryItems: [URLQueryItem] = []) {
        self.path = path
        self.queryItems = queryItems
    }

    // MARK: Authentication

    /// GET /authentication
    static var authentication: TMDBEndpoint {
        TMDBEndpoint(path: "/authentication")
    }

    // MARK: Lists

    /// GET /trending/{scope}/{window}
    static func trending(scope: TrendingScope, window: TrendingWindow, page: Int) -> TMDBEndpoint {
        TMDBEndpoint(path: "/trending/\(scope.rawValue)/\(window.rawValue)", queryItems: [pageItem(page)])
    }

    /// GET /tv/{list} for airing_today, on_the_air, popular, top_rated
    static func tvList(_ list: String, page: Int) -> TMDBEndpoint {
        TMDBEndpoint(path: "/tv/\(list)", queryItems: [pageItem(page)])
    }

    /// GET /movie/{list} for now_playing, upcoming, popular, top_rated; `region` is added when given.
    static func movieList(_ list: String, page: Int, region: String? = nil) -> TMDBEndpoint {
        var items: [URLQueryItem] = [pageItem(page)]
        if let region = region, !region.isEmpty {
            items.append(URLQueryItem(name: "region", value: region))
        }
        return TMDBEndpoint(path: "/movie/\(list)", queryItems: items)
    }

    // MARK: Search

    /// GET /search/multi, /search/tv or /search/movie with include_adult=false.
    static func search(query: String, kind: MediaKind?, page: Int) -> TMDBEndpoint {
        let segment: String
        switch kind {
        case .none: segment = "multi"
        case .some(.show): segment = "tv"
        case .some(.movie): segment = "movie"
        }
        return TMDBEndpoint(
            path: "/search/\(segment)",
            queryItems: [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "include_adult", value: "false"),
                pageItem(page)
            ]
        )
    }

    // MARK: Details

    /// GET /tv/{id}
    static func tvDetails(id: Int) -> TMDBEndpoint {
        TMDBEndpoint(path: "/tv/\(id)")
    }

    /// GET /tv/{id}/season/{number}
    static func tvSeason(showID: Int, number: Int) -> TMDBEndpoint {
        TMDBEndpoint(path: "/tv/\(showID)/season/\(number)")
    }

    /// GET /movie/{id}
    static func movieDetails(id: Int) -> TMDBEndpoint {
        TMDBEndpoint(path: "/movie/\(id)")
    }

    // MARK: Helpers

    private static func pageItem(_ page: Int) -> URLQueryItem {
        URLQueryItem(name: "page", value: String(max(page, 1)))
    }
}
