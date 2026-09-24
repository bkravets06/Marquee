import Foundation

// MARK: - EpisodePointer

/// A "last watched" pointer into a show. `(0, 0)` means not started.
/// Specials (season 0) are ignored by `NextUp`.
public struct EpisodePointer: Hashable, Comparable, Codable, Sendable {
    public var season: Int
    public var episode: Int

    public init(season: Int, episode: Int) {
        self.season = season
        self.episode = episode
    }

    /// The pointer that means "nothing watched yet": season 0, episode 0.
    public static let notStarted = EpisodePointer(season: 0, episode: 0)

    /// `true` when the pointer differs from `notStarted`.
    public var isStarted: Bool { self != EpisodePointer.notStarted }

    /// Short label such as "S2 E5".
    public var label: String { "S\(season) E\(episode)" }

    // MARK: Comparable

    public static func < (lhs: EpisodePointer, rhs: EpisodePointer) -> Bool {
        if lhs.season != rhs.season {
            return lhs.season < rhs.season
        }
        return lhs.episode < rhs.episode
    }
}
