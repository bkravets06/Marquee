import Foundation

// MARK: - TMDBImage

/// Builds image URLs from raw TMDB image paths ("/abc.jpg").
public enum TMDBImage {
    public enum PosterSize: String, Sendable { case w92, w154, w185, w342, w500, w780, original }
    public enum BackdropSize: String, Sendable { case w300, w780, w1280, original }
    public enum StillSize: String, Sendable { case w92, w185, w300, original }
    public enum LogoSize: String, Sendable { case w45, w92, w154, w185, w300, w500, original }

    public static let baseURL = URL(string: "https://image.tmdb.org/t/p/")!

    /// Poster URL for a TMDB `poster_path`.
    public static func poster(_ path: String?, size: PosterSize = .w342) -> URL? {
        url(path: path, size: size.rawValue)
    }

    /// Backdrop URL for a TMDB `backdrop_path`.
    public static func backdrop(_ path: String?, size: BackdropSize = .w780) -> URL? {
        url(path: path, size: size.rawValue)
    }

    /// Episode still URL for a TMDB `still_path`.
    public static func still(_ path: String?, size: StillSize = .w300) -> URL? {
        url(path: path, size: size.rawValue)
    }

    /// Watch provider or network logo URL for a TMDB `logo_path`.
    public static func logo(_ path: String?, size: LogoSize = .w92) -> URL? {
        url(path: path, size: size.rawValue)
    }

    /// Generic builder: `baseURL/<size>/<path>`. Returns `nil` for a missing or empty path.
    public static func url(path: String?, size: String) -> URL? {
        guard let raw = path?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        let trimmedPath = raw.hasPrefix("/") ? String(raw.dropFirst()) : raw
        guard !trimmedPath.isEmpty else { return nil }
        return URL(string: baseURL.absoluteString + size + "/" + trimmedPath)
    }
}
