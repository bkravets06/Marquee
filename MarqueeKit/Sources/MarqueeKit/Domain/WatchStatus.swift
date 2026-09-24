import Foundation

// MARK: - WatchStatus

/// Where an item sits in the user's library.
public enum WatchStatus: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case watching
    case watchlist
    case watched

    public var id: String { rawValue }

    /// User-facing name ("Watching", "Watchlist", "Watched").
    public var displayName: String {
        switch self {
        case .watching: return "Watching"
        case .watchlist: return "Watchlist"
        case .watched: return "Watched"
        }
    }

    /// SF Symbol name for the status ("play.circle", "bookmark", "checkmark.circle").
    public var symbolName: String {
        switch self {
        case .watching: return "play.circle"
        case .watchlist: return "bookmark"
        case .watched: return "checkmark.circle"
        }
    }
}
