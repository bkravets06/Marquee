import Foundation

// MARK: - NextUp

/// Pure episode arithmetic over a show's regular seasons.
///
/// Season 0 (specials) is ignored, seasons are always considered in ascending
/// order, and seasons that report zero episodes are skipped when stepping.
public enum NextUp {

    // MARK: Public API

    /// The next unwatched episode after `pointer`, or `nil` when caught up (or when there are no seasons).
    public static func next(after pointer: EpisodePointer, in seasons: [SeasonInfo]) -> EpisodePointer? {
        let regular = steppableSeasons(in: seasons)
        guard let first = regular.first else { return nil }

        // Not started, or pointing into specials: the first regular episode is next.
        guard pointer.isStarted, pointer.season >= 1 else {
            return EpisodePointer(season: first.number, episode: 1)
        }

        if let index = regular.firstIndex(where: { $0.number == pointer.season }) {
            let season = regular[index]
            if pointer.episode < season.episodeCount {
                return EpisodePointer(season: season.number, episode: max(pointer.episode, 0) + 1)
            }
            // The pointer sits at (or beyond) the end of this season: roll over.
            let nextIndex = index + 1
            guard nextIndex < regular.count else { return nil }
            return EpisodePointer(season: regular[nextIndex].number, episode: 1)
        }

        // The pointer's season is unknown or empty: continue with the next season after it.
        guard let following = regular.first(where: { $0.number > pointer.season }) else { return nil }
        return EpisodePointer(season: following.number, episode: 1)
    }

    /// Total number of regular episodes (season >= 1).
    public static func totalEpisodes(in seasons: [SeasonInfo]) -> Int {
        seasons.filter { $0.number >= 1 }.reduce(0) { $0 + max($1.episodeCount, 0) }
    }

    /// Number of regular episodes at or before `pointer` (the progress numerator).
    public static func watchedCount(upTo pointer: EpisodePointer, in seasons: [SeasonInfo]) -> Int {
        guard pointer.isStarted, pointer.season >= 1 else { return 0 }
        var count = 0
        for season in regularSeasons(in: seasons) where season.number <= pointer.season {
            if season.number < pointer.season {
                count += max(season.episodeCount, 0)
            } else {
                count += min(max(pointer.episode, 0), max(season.episodeCount, 0))
            }
        }
        return count
    }

    /// The pointer immediately before `pointer` (for "mark unwatched"); `.notStarted` if there is none.
    public static func previous(before pointer: EpisodePointer, in seasons: [SeasonInfo]) -> EpisodePointer {
        guard pointer.isStarted, pointer.season >= 1 else { return .notStarted }
        let regular = steppableSeasons(in: seasons)

        var effectiveEpisode = pointer.episode
        if let season = regular.first(where: { $0.number == pointer.season }) {
            effectiveEpisode = min(pointer.episode, season.episodeCount)
        }
        if effectiveEpisode > 1 {
            return EpisodePointer(season: pointer.season, episode: effectiveEpisode - 1)
        }

        guard let prior = regular.last(where: { $0.number < pointer.season }) else { return .notStarted }
        return EpisodePointer(season: prior.number, episode: prior.episodeCount)
    }

    // MARK: Helpers

    /// Regular seasons (number >= 1) sorted ascending, including empty ones.
    static func regularSeasons(in seasons: [SeasonInfo]) -> [SeasonInfo] {
        seasons.filter { $0.number >= 1 }.sorted { $0.number < $1.number }
    }

    /// Regular seasons that actually contain episodes, sorted ascending.
    static func steppableSeasons(in seasons: [SeasonInfo]) -> [SeasonInfo] {
        regularSeasons(in: seasons).filter { $0.episodeCount > 0 }
    }
}
