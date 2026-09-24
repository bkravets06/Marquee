import Foundation
import MarqueeKit

// MARK: - Typed accessors

extension MediaItem {

    private static let jsonEncoder = JSONEncoder()
    private static let jsonDecoder = JSONDecoder()

    /// Typed view of `kindRaw`. Unknown raw values fall back to `.show`.
    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .show }
        set { kindRaw = newValue.rawValue }
    }

    /// Typed view of `statusRaw`. Unknown raw values fall back to `.watchlist`.
    var status: WatchStatus {
        get { WatchStatus(rawValue: statusRaw) ?? .watchlist }
        set { statusRaw = newValue.rawValue }
    }

    /// Regular seasons (number >= 1), decoded from `seasonsData`.
    var seasons: [SeasonInfo] {
        get {
            guard let data = seasonsData else { return [] }
            return (try? Self.jsonDecoder.decode([SeasonInfo].self, from: data)) ?? []
        }
        set {
            if newValue.isEmpty {
                seasonsData = nil
            } else {
                seasonsData = try? Self.jsonEncoder.encode(newValue)
            }
        }
    }

    /// Weekly release cadence for custom shows, decoded from `releaseScheduleData`.
    var releaseSchedule: ReleaseSchedule? {
        get {
            guard let data = releaseScheduleData else { return nil }
            return try? Self.jsonDecoder.decode(ReleaseSchedule.self, from: data)
        }
        set {
            releaseScheduleData = newValue.flatMap { try? Self.jsonEncoder.encode($0) }
        }
    }

    /// Last watched pointer; `.notStarted` when nothing has been watched.
    var progress: EpisodePointer {
        get { EpisodePointer(season: progressSeason, episode: progressEpisode) }
        set {
            progressSeason = newValue.season
            progressEpisode = newValue.episode
        }
    }

    /// The next episode the user should watch, or `nil` when caught up.
    ///
    /// TMDB shows walk `seasons`. Custom shows without season data count
    /// episodes upward until `totalEpisodes` (when set) is reached.
    var nextUp: EpisodePointer? {
        guard isShow else { return nil }
        let knownSeasons = seasons
        if !knownSeasons.isEmpty {
            return NextUp.next(after: progress, in: knownSeasons)
        }
        guard isCustom else { return nil }
        if let total = totalEpisodes, total > 0, progress.episode >= total {
            return nil
        }
        return EpisodePointer(season: max(progress.season, 1), episode: progress.episode + 1)
    }

    /// Pointer for the next episode TMDB says will air, if known.
    var nextEpisodePointer: EpisodePointer? {
        guard let season = nextEpisodeSeason, let number = nextEpisodeNumber else { return nil }
        return EpisodePointer(season: season, episode: number)
    }
}

// MARK: - Kind helpers

extension MediaItem {

    var isShow: Bool { kind == .show }

    var isMovie: Bool { kind == .movie }

    /// Release year derived from `releaseDate`.
    var year: Int? {
        guard let date = releaseDate else { return nil }
        return Calendar.current.component(.year, from: date)
    }

    /// TMDB poster URL; `nil` for custom items or items without a poster.
    func posterURL(size: TMDBImage.PosterSize = .w342) -> URL? {
        TMDBImage.poster(posterPath, size: size)
    }

    /// TMDB backdrop URL; `nil` when no backdrop is known.
    func backdropURL(size: TMDBImage.BackdropSize = .w780) -> URL? {
        TMDBImage.backdrop(backdropPath, size: size)
    }
}

// MARK: - Progress

extension MediaItem {

    /// Number of regular episodes watched so far (progress numerator).
    var watchedEpisodeCount: Int {
        let knownSeasons = seasons
        if !knownSeasons.isEmpty {
            return NextUp.watchedCount(upTo: progress, in: knownSeasons)
        }
        return max(progress.episode, 0)
    }

    /// Total regular episodes: from season data when available, else `totalEpisodes`.
    var episodeTotal: Int? {
        let knownSeasons = seasons
        if !knownSeasons.isEmpty {
            return NextUp.totalEpisodes(in: knownSeasons)
        }
        return totalEpisodes
    }

    /// Watched fraction in 0...1, or `nil` when the total is unknown or zero.
    var progressFraction: Double? {
        guard let total = episodeTotal, total > 0 else { return nil }
        let fraction = Double(watchedEpisodeCount) / Double(total)
        return min(max(fraction, 0), 1)
    }

    /// Whether the next known episode airs between the start of today and
    /// `days` days from now (inclusive).
    func airsWithinDays(_ days: Int, now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard let airDate = nextEpisodeAirDate else { return false }
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else { return false }
        return airDate >= start && airDate <= end
    }

    /// "S3 E4 · Thu" style label for the next episode, or `nil` when unknown.
    var nextEpisodeLabel: String? {
        if let pointer = nextEpisodePointer, let airDate = nextEpisodeAirDate {
            return "\(pointer.label) · \(Formatters.relativeAirDate(airDate))"
        }
        if let airDate = nextEpisodeAirDate {
            return Formatters.relativeAirDate(airDate)
        }
        if let pointer = nextEpisodePointer {
            return pointer.label
        }
        if isCustom,
           let schedule = releaseSchedule,
           let next = schedule.nextOccurrence(after: .now),
           let upcoming = nextUp {
            return "\(upcoming.label) · \(Formatters.relativeAirDate(next))"
        }
        return nil
    }
}
