import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - TrendingScope / TrendingWindow

public enum TrendingScope: String, Sendable {
    case all
    case tv
    case movie
}

public enum TrendingWindow: String, Sendable {
    case day
    case week
}

// MARK: - TMDBClient

/// Async client for the TMDB v3 API. All calls go through `makeRequest(_:)` and a
/// single transport closure so tests can drive the client without a network.
public actor TMDBClient {

    /// Sends a request and returns the raw response. The public initializer wires this to `URLSession`.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    public static let baseURL = URL(string: "https://api.themoviedb.org/3")!

    private let credential: TMDBCredential
    private let language: String
    private let region: String?
    private let baseURL: URL
    private let transport: Transport
    private let decoder: JSONDecoder

    // MARK: Initializers

    public init(
        credential: TMDBCredential,
        session: URLSession = .shared,
        language: String = "en-US",
        region: String? = Locale.current.region?.identifier,
        baseURL: URL = TMDBClient.baseURL
    ) {
        self.credential = credential
        self.language = language
        self.region = region
        self.baseURL = baseURL
        self.transport = { request in
            try await session.data(for: request)
        }
        self.decoder = JSONDecoder()
    }

    /// Test seam: identical to the public initializer but with an injected transport.
    init(
        credential: TMDBCredential,
        language: String = "en-US",
        region: String? = nil,
        baseURL: URL = TMDBClient.baseURL,
        transport: @escaping Transport
    ) {
        self.credential = credential
        self.language = language
        self.region = region
        self.baseURL = baseURL
        self.transport = transport
        self.decoder = JSONDecoder()
    }

    // MARK: Authentication

    /// `GET /authentication`. Returns TMDB's `success` flag; a rejected credential throws `.unauthorized`.
    public func validateCredentials() async throws -> Bool {
        let status: TMDBStatusResponse = try await fetch(TMDBStatusResponse.self, from: .authentication)
        return status.success ?? true
    }

    // MARK: Trending

    /// `GET /trending/{scope}/{window}`. Person rows are dropped for `.all`.
    public func trending(_ scope: TrendingScope = .all, window: TrendingWindow = .day, page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        let endpoint = TMDBEndpoint.trending(scope: scope, window: window, page: page)
        switch scope {
        case .all:
            return try await fetchMultiList(endpoint)
        case .tv:
            return try await fetchTVList(endpoint)
        case .movie:
            return try await fetchMovieList(endpoint)
        }
    }

    // MARK: Shows

    /// `GET /tv/airing_today`
    public func airingToday(page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        try await fetchTVList(.tvList("airing_today", page: page))
    }

    /// `GET /tv/on_the_air`
    public func onTheAir(page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        try await fetchTVList(.tvList("on_the_air", page: page))
    }

    /// `GET /tv/popular`
    public func popularShows(page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        try await fetchTVList(.tvList("popular", page: page))
    }

    /// `GET /tv/top_rated`
    public func topRatedShows(page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        try await fetchTVList(.tvList("top_rated", page: page))
    }

    // MARK: Movies

    /// `GET /movie/now_playing` (uses `region` when set)
    public func nowPlayingMovies(page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        try await fetchMovieList(.movieList("now_playing", page: page, region: region))
    }

    /// `GET /movie/upcoming` (uses `region` when set)
    public func upcomingMovies(page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        try await fetchMovieList(.movieList("upcoming", page: page, region: region))
    }

    /// `GET /movie/popular`
    public func popularMovies(page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        try await fetchMovieList(.movieList("popular", page: page))
    }

    /// `GET /movie/top_rated`
    public func topRatedMovies(page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        try await fetchMovieList(.movieList("top_rated", page: page))
    }

    // MARK: Search

    /// `nil` kind searches `/search/multi` (person rows dropped, `totalResults` left as reported);
    /// `.show` searches `/search/tv`; `.movie` searches `/search/movie`. Always `include_adult=false`.
    public func search(_ query: String, kind: MediaKind? = nil, page: Int = 1) async throws -> PagedResponse<MediaSummary> {
        let endpoint = TMDBEndpoint.search(query: query, kind: kind, page: page)
        switch kind {
        case .none:
            return try await fetchMultiList(endpoint)
        case .some(.show):
            return try await fetchTVList(endpoint)
        case .some(.movie):
            return try await fetchMovieList(endpoint)
        }
    }

    // MARK: Details

    /// `GET /tv/{id}`
    public func showDetails(id: Int) async throws -> TVShowDetails {
        try await fetch(TVShowDetails.self, from: .tvDetails(id: id))
    }

    /// `GET /tv/{id}/season/{number}`
    public func season(showID: Int, number: Int) async throws -> SeasonDetails {
        try await fetch(SeasonDetails.self, from: .tvSeason(showID: showID, number: number))
    }

    /// `GET /movie/{id}`
    public func movieDetails(id: Int) async throws -> MovieDetails {
        try await fetch(MovieDetails.self, from: .movieDetails(id: id))
    }

    // MARK: Request building

    /// Builds the `URLRequest` for `endpoint`: base URL + path, endpoint query items plus `language`
    /// (and `api_key` for v3 keys) sorted by name, and a `Bearer` header for v4 tokens.
    nonisolated func makeRequest(_ endpoint: TMDBEndpoint) -> URLRequest {
        var items: [URLQueryItem] = endpoint.queryItems
        items.append(URLQueryItem(name: "language", value: language))
        if case .apiKey(let key) = credential {
            items.append(URLQueryItem(name: "api_key", value: key))
        }
        items.sort { $0.name < $1.name }

        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) ?? URLComponents()
        var basePath = components.path
        while basePath.hasSuffix("/") {
            basePath.removeLast()
        }
        let endpointPath = endpoint.path.hasPrefix("/") ? endpoint.path : "/" + endpoint.path
        components.path = basePath + endpointPath
        components.queryItems = items

        var request = URLRequest(url: components.url ?? baseURL)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if case .bearer(let token) = credential {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: List helpers

    private func fetchTVList(_ endpoint: TMDBEndpoint) async throws -> PagedResponse<MediaSummary> {
        let page = try await fetch(PagedResponse<RawTVResult>.self, from: endpoint)
        return page.map { $0.summary }
    }

    private func fetchMovieList(_ endpoint: TMDBEndpoint) async throws -> PagedResponse<MediaSummary> {
        let page = try await fetch(PagedResponse<RawMovieResult>.self, from: endpoint)
        return page.map { $0.summary }
    }

    private func fetchMultiList(_ endpoint: TMDBEndpoint) async throws -> PagedResponse<MediaSummary> {
        let page = try await fetch(PagedResponse<RawMultiResult>.self, from: endpoint)
        return page.compactMap { $0.summary }
    }

    // MARK: Transport

    private func fetch<Value: Decodable>(_ type: Value.Type, from endpoint: TMDBEndpoint) async throws -> Value {
        guard credential.isUsable else { throw TMDBError.missingCredentials }
        let request = makeRequest(endpoint)
        let (data, response) = try await send(request)
        if let http = response as? HTTPURLResponse {
            try TMDBClient.validate(http, data: data)
        }
        do {
            return try decoder.decode(Value.self, from: data)
        } catch let error as DecodingError {
            throw TMDBError.decoding(TMDBClient.describe(error))
        } catch {
            throw TMDBError.decoding(error.localizedDescription)
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await transport(request)
        } catch let error as TMDBError {
            throw error
        } catch let error as URLError {
            throw TMDBError.network(error.localizedDescription)
        } catch {
            throw TMDBError.network(error.localizedDescription)
        }
    }

    // MARK: Error mapping

    /// Maps non-2xx responses: 401 → `.unauthorized`, 404 → `.notFound`, 429 → `.rateLimited`,
    /// anything else → `.http(status:message:)` with TMDB's `status_message` when present.
    static func validate(_ response: HTTPURLResponse, data: Data) throws {
        let status = response.statusCode
        if (200..<300).contains(status) { return }
        switch status {
        case 401:
            throw TMDBError.unauthorized
        case 404:
            throw TMDBError.notFound
        case 429:
            throw TMDBError.rateLimited(retryAfter: retryAfterSeconds(from: response))
        default:
            throw TMDBError.http(status: status, message: statusMessage(in: data))
        }
    }

    /// Parses an integer `Retry-After` header (case-insensitively). HTTP-date values yield `nil`.
    static func retryAfterSeconds(from response: HTTPURLResponse) -> Int? {
        for (key, value) in response.allHeaderFields {
            let name = String(describing: key).lowercased()
            guard name == "retry-after" else { continue }
            let text = String(describing: value).trimmingCharacters(in: .whitespacesAndNewlines)
            if let seconds = Int(text) {
                return max(seconds, 0)
            }
            if let seconds = Double(text) {
                return max(Int(seconds.rounded(.up)), 0)
            }
            return nil
        }
        return nil
    }

    /// TMDB's `status_message` from an error body, if the body is a status envelope.
    static func statusMessage(in data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        guard let envelope = try? JSONDecoder().decode(TMDBStatusResponse.self, from: data) else { return nil }
        return envelope.statusMessage
    }

    /// A compact, human-readable description of a `DecodingError`.
    static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            let keys = context.codingPath.map { $0.stringValue }
            return keys.isEmpty ? "root" : keys.joined(separator: ".")
        }
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing key \"\(key.stringValue)\" at \(path(context))."
        case .typeMismatch(let type, let context):
            return "Type mismatch for \(type) at \(path(context))."
        case .valueNotFound(let type, let context):
            return "Missing value of type \(type) at \(path(context))."
        case .dataCorrupted(let context):
            let detail = context.debugDescription
            return detail.isEmpty ? "Corrupted data at \(path(context))." : detail
        @unknown default:
            return error.localizedDescription
        }
    }
}
