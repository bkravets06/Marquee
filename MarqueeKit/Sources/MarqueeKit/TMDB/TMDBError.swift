import Foundation

// MARK: - TMDBError

/// Errors produced by `TMDBClient`, already mapped from transport and HTTP failures.
public enum TMDBError: Error, LocalizedError, Sendable, Equatable {
    /// No usable credential was configured.
    case missingCredentials
    /// HTTP 401.
    case unauthorized
    /// HTTP 404.
    case notFound
    /// HTTP 429, with the parsed `Retry-After` value in seconds when present.
    case rateLimited(retryAfter: Int?)
    /// Any other non-2xx status, with TMDB's `status_message` when present.
    case http(status: Int, message: String?)
    /// The response body could not be decoded.
    case decoding(String)
    /// The request never produced a response (URLError and friends).
    case network(String)

    // MARK: LocalizedError

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "Add a TMDB API key or access token in Settings to continue."
        case .unauthorized:
            return "Your TMDB API key was rejected."
        case .notFound:
            return "TMDB could not find that title."
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter, seconds > 0 {
                return "TMDB is limiting requests. Try again in \(seconds) seconds."
            }
            return "TMDB is limiting requests. Try again shortly."
        case .http(let status, let message):
            if let message = message, !message.isEmpty {
                return "TMDB returned an error (HTTP \(status)): \(message)"
            }
            return "TMDB returned an unexpected response (HTTP \(status))."
        case .decoding(let detail):
            if detail.isEmpty {
                return "TMDB returned data that could not be read."
            }
            return "TMDB returned data that could not be read. (\(detail))"
        case .network(let detail):
            if detail.isEmpty {
                return "The network request to TMDB failed."
            }
            return detail
        }
    }
}
