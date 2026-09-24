import Foundation
import SwiftData
import MarqueeKit

// MARK: - MediaItem

/// A show or movie in the user's library.
///
/// TMDB-backed items carry a `tmdbID`; custom items are user-entered and have
/// `isCustom == true`. Structured values (seasons, release schedule) are
/// persisted as JSON `Data` and exposed through the computed accessors in
/// `MediaItem+Convenience.swift`.
@Model
final class MediaItem {

    // MARK: Identity

    @Attribute(.unique) var id: UUID
    /// TMDB identifier; `nil` for custom items.
    var tmdbID: Int?
    /// `MediaKind.rawValue`. Use `kind` from the convenience extension.
    var kindRaw: String
    /// `WatchStatus.rawValue`. Use `status` from the convenience extension.
    var statusRaw: String

    // MARK: Metadata

    var title: String
    var overview: String
    var tagline: String?
    /// Raw TMDB poster path ("/abc.jpg").
    var posterPath: String?
    /// Raw TMDB backdrop path ("/abc.jpg").
    var backdropPath: String?
    /// User-supplied JPEG poster for custom items (<= 600px on the long side).
    @Attribute(.externalStorage) var customPosterData: Data?
    /// Local start of day of the first air date / release date.
    var releaseDate: Date?
    var genres: [String]
    var runtimeMinutes: Int?
    var voteAverage: Double?
    /// TMDB status string for shows ("Returning Series", "Ended", ...).
    var showStatus: String?

    // MARK: Episodes and progress

    /// JSON-encoded `[SeasonInfo]` (regular seasons only).
    var seasonsData: Data?
    /// TMDB `numberOfEpisodes`, or user-entered for custom shows.
    var totalEpisodes: Int?
    /// Last watched pointer season; 0/0 means not started.
    var progressSeason: Int
    /// Last watched pointer episode; 0/0 means not started.
    var progressEpisode: Int
    var notificationsEnabled: Bool
    /// Local start of day of the next episode's air date.
    var nextEpisodeAirDate: Date?
    var nextEpisodeSeason: Int?
    var nextEpisodeNumber: Int?
    var nextEpisodeName: String?
    /// JSON-encoded `ReleaseSchedule` (custom shows).
    var releaseScheduleData: Data?

    // MARK: User data

    var isCustom: Bool
    var linkURL: URL?
    var notes: String
    /// 1...5, optional.
    var userRating: Int?

    // MARK: Timestamps

    var addedAt: Date
    var updatedAt: Date
    var lastWatchedAt: Date?
    var finishedAt: Date?
    var lastRefreshedAt: Date?

    // MARK: Init

    /// Creates a library item. Only `kind`, `status` and `title` are required;
    /// everything else has a sensible default.
    init(
        kind: MediaKind,
        status: WatchStatus,
        title: String,
        tmdbID: Int? = nil,
        overview: String = "",
        tagline: String? = nil,
        posterPath: String? = nil,
        backdropPath: String? = nil,
        customPosterData: Data? = nil,
        releaseDate: Date? = nil,
        genres: [String] = [],
        runtimeMinutes: Int? = nil,
        voteAverage: Double? = nil,
        showStatus: String? = nil,
        totalEpisodes: Int? = nil,
        isCustom: Bool = false,
        linkURL: URL? = nil,
        notes: String = "",
        notificationsEnabled: Bool = false
    ) {
        let now = Date.now
        self.id = UUID()
        self.tmdbID = tmdbID
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.title = title
        self.overview = overview
        self.tagline = tagline
        self.posterPath = posterPath
        self.backdropPath = backdropPath
        self.customPosterData = customPosterData
        self.releaseDate = releaseDate
        self.genres = genres
        self.runtimeMinutes = runtimeMinutes
        self.voteAverage = voteAverage
        self.showStatus = showStatus
        self.seasonsData = nil
        self.totalEpisodes = totalEpisodes
        self.progressSeason = 0
        self.progressEpisode = 0
        self.notificationsEnabled = notificationsEnabled
        self.nextEpisodeAirDate = nil
        self.nextEpisodeSeason = nil
        self.nextEpisodeNumber = nil
        self.nextEpisodeName = nil
        self.releaseScheduleData = nil
        self.isCustom = isCustom
        self.linkURL = linkURL
        self.notes = notes
        self.userRating = nil
        self.addedAt = now
        self.updatedAt = now
        self.lastWatchedAt = nil
        self.finishedAt = nil
        self.lastRefreshedAt = nil
    }
}
