import Foundation

// MARK: - MediaKind

/// The two kinds of catalog entries Marquee tracks.
public enum MediaKind: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case show
    case movie

    public var id: String { rawValue }

    /// Singular, user-facing name ("Show" / "Movie").
    public var displayName: String {
        switch self {
        case .show: return "Show"
        case .movie: return "Movie"
        }
    }

    /// Plural, user-facing name ("Shows" / "Movies").
    public var pluralDisplayName: String {
        switch self {
        case .show: return "Shows"
        case .movie: return "Movies"
        }
    }

    /// SF Symbol name that represents the kind ("tv" / "film").
    public var symbolName: String {
        switch self {
        case .show: return "tv"
        case .movie: return "film"
        }
    }
}
