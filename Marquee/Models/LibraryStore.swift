import Foundation
import SwiftData
import MarqueeKit
import os

private let logger = Logger(subsystem: "com.bjkravets.marquee", category: "LibraryStore")

// MARK: - LibraryStore

/// All reads and mutations of `MediaItem`s go through this type so that
/// timestamps, status transitions and saving stay consistent.
@MainActor
struct LibraryStore {

    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: Lookup

    /// The item with the given library identifier, if any.
    func item(id: UUID) -> MediaItem? {
        let target = id
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in item.id == target }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    /// The TMDB-backed item with the given id and kind, if any.
    func item(tmdbID: Int, kind: MediaKind) -> MediaItem? {
        let targetID: Int? = tmdbID
        let kindRaw = kind.rawValue
        var descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in
                item.tmdbID == targetID && item.kindRaw == kindRaw
            }
        )
        descriptor.fetchLimit = 1
        return fetch(descriptor).first
    }

    /// Every item, most recently updated first.
    func allItems() -> [MediaItem] {
        let descriptor = FetchDescriptor<MediaItem>(
            sortBy: [SortDescriptor(\MediaItem.updatedAt, order: .reverse)]
        )
        return fetch(descriptor)
    }

    /// Items with the given status, most recently updated first.
    func items(status: WatchStatus) -> [MediaItem] {
        let statusRaw = status.rawValue
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in item.statusRaw == statusRaw },
            sortBy: [SortDescriptor(\MediaItem.updatedAt, order: .reverse)]
        )
        return fetch(descriptor)
    }

    /// Library status of a catalog result, or `nil` when it is not in the library.
    func status(of summary: MediaSummary) -> WatchStatus? {
        item(tmdbID: summary.id, kind: summary.kind)?.status
    }

    // MARK: Adding

    /// Adds a TMDB result to the library. Idempotent: an existing item just
    /// has its status updated.
    @discardableResult
    func add(_ summary: MediaSummary, status: WatchStatus) -> MediaItem {
        if let existing = item(tmdbID: summary.id, kind: summary.kind) {
            setStatus(existing, to: status)
            return existing
        }
        let item = MediaItem(
            kind: summary.kind,
            status: status,
            title: summary.title,
            tmdbID: summary.id,
            overview: summary.overview,
            posterPath: summary.posterPath,
            backdropPath: summary.backdropPath,
            releaseDate: summary.releaseDate?.startOfDay(),
            genres: summary.genreNames,
            voteAverage: summary.voteAverage > 0 ? summary.voteAverage : nil
        )
        if status == .watched {
            let now = Date.now
            item.finishedAt = now
            item.lastWatchedAt = now
        }
        context.insert(item)
        save()
        return item
    }

    /// Adds a user-entered item that is not backed by TMDB.
    @discardableResult
    func addCustom(
        title: String,
        kind: MediaKind,
        status: WatchStatus,
        overview: String,
        posterData: Data?,
        linkURL: URL?,
        notes: String,
        totalEpisodes: Int?,
        schedule: ReleaseSchedule?,
        notificationsEnabled: Bool
    ) -> MediaItem {
        let item = MediaItem(
            kind: kind,
            status: status,
            title: title,
            overview: overview,
            customPosterData: posterData,
            totalEpisodes: kind == .show ? totalEpisodes : nil,
            isCustom: true,
            linkURL: linkURL,
            notes: notes,
            notificationsEnabled: kind == .show && notificationsEnabled
        )
        if kind == .show {
            item.releaseSchedule = schedule
        }
        if status == .watched {
            let now = Date.now
            item.finishedAt = now
            item.lastWatchedAt = now
        }
        context.insert(item)
        save()
        return item
    }

    // MARK: Applying TMDB details

    /// Copies fresh TMDB show details onto `item`. `updatedAt` is bumped only
    /// when something the user can see (episodes, status, seasons) changed, so
    /// routine refreshes do not reshuffle "Recently updated" ordering.
    func apply(_ details: TVShowDetails, to item: MediaItem) {
        let before = ShowSnapshot(item: item)

        if item.tmdbID == nil {
            item.tmdbID = details.id
        }
        item.title = details.name
        item.overview = details.overview
        item.tagline = nilIfEmpty(details.tagline)
        item.posterPath = details.posterPath
        item.backdropPath = details.backdropPath
        item.releaseDate = details.firstAirDate?.startOfDay()
        item.genres = details.genres.map { $0.name }
        item.runtimeMinutes = details.episodeRunTime.first
        item.voteAverage = details.voteAverage > 0 ? details.voteAverage : nil
        item.showStatus = nilIfEmpty(details.status)
        item.seasons = details.seasonInfos
        item.totalEpisodes = details.numberOfEpisodes > 0 ? details.numberOfEpisodes : nil

        if let next = details.nextEpisodeToAir {
            item.nextEpisodeAirDate = next.airDate?.startOfDay()
            item.nextEpisodeSeason = next.seasonNumber
            item.nextEpisodeNumber = next.episodeNumber
            item.nextEpisodeName = nilIfEmpty(next.name)
        } else {
            item.nextEpisodeAirDate = nil
            item.nextEpisodeSeason = nil
            item.nextEpisodeNumber = nil
            item.nextEpisodeName = nil
        }

        let now = Date.now
        item.lastRefreshedAt = now
        if ShowSnapshot(item: item) != before {
            item.updatedAt = now
        }
        save()
    }

    /// Copies fresh TMDB movie details onto `item`.
    func apply(_ details: MovieDetails, to item: MediaItem) {
        if item.tmdbID == nil {
            item.tmdbID = details.id
        }
        let previousRelease = item.releaseDate
        item.title = details.title
        item.overview = details.overview
        item.tagline = nilIfEmpty(details.tagline)
        item.posterPath = details.posterPath
        item.backdropPath = details.backdropPath
        item.releaseDate = details.releaseDate?.startOfDay()
        item.genres = details.genres.map { $0.name }
        item.runtimeMinutes = details.runtime
        item.voteAverage = details.voteAverage > 0 ? details.voteAverage : nil
        item.showStatus = nilIfEmpty(details.status)

        let now = Date.now
        item.lastRefreshedAt = now
        if item.releaseDate != previousRelease {
            item.updatedAt = now
        }
        save()
    }

    // MARK: Status and progress

    /// Moves an item between Watching / Watchlist / Watched.
    func setStatus(_ item: MediaItem, to status: WatchStatus) {
        let now = Date.now
        let previous = item.status
        item.status = status
        switch status {
        case .watched:
            item.finishedAt = now
            item.lastWatchedAt = now
        case .watching, .watchlist:
            if previous == .watched {
                item.finishedAt = nil
            }
        }
        item.updatedAt = now
        save()
    }

    /// Sets the last-watched pointer. Starting to watch promotes a watchlist
    /// item to Watching.
    func setProgress(_ item: MediaItem, to pointer: EpisodePointer) {
        let now = Date.now
        item.progress = pointer
        if pointer.isStarted {
            item.lastWatchedAt = now
        }
        if item.status == .watchlist {
            item.status = .watching
        }
        item.updatedAt = now
        save()
    }

    /// Advances progress to `item.nextUp`. No-op for movies or when caught up.
    func markNextEpisodeWatched(_ item: MediaItem) {
        guard item.isShow, let next = item.nextUp else { return }
        setProgress(item, to: next)
    }

    /// Steps progress back one episode. No-op when nothing has been watched.
    func markPreviousEpisodeUnwatched(_ item: MediaItem) {
        guard item.isShow, item.progress.isStarted else { return }
        let current = item.progress
        let knownSeasons = item.seasons
        let previous: EpisodePointer
        if !knownSeasons.isEmpty {
            previous = NextUp.previous(before: current, in: knownSeasons)
        } else if current.episode > 1 {
            previous = EpisodePointer(season: current.season, episode: current.episode - 1)
        } else {
            previous = .notStarted
        }
        let now = Date.now
        item.progress = previous
        if item.status == .watched {
            item.status = .watching
            item.finishedAt = nil
        }
        item.updatedAt = now
        save()
    }

    /// Marks a movie as watched.
    func markMovieWatched(_ item: MediaItem) {
        setStatus(item, to: .watched)
    }

    /// Toggles new-episode reminders for a show.
    func setNotifications(_ item: MediaItem, enabled: Bool) {
        item.notificationsEnabled = enabled
        item.updatedAt = .now
        save()
    }

    // MARK: Deleting

    /// Removes an item from the library.
    func delete(_ item: MediaItem) {
        context.delete(item)
        save()
    }

    /// Removes every item from the library.
    func deleteAll() {
        for item in fetch(FetchDescriptor<MediaItem>()) {
            context.delete(item)
        }
        save()
    }

    /// Persists pending changes, logging (not throwing) on failure.
    func save() {
        do {
            try context.save()
        } catch {
            logger.error("Failed to save library: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Refresh queries

    /// TMDB shows worth refreshing: those in Watching / Watchlist, or with
    /// reminders on, whose last refresh is missing or at least `interval` old.
    /// Pass `olderThan: 0` to force every eligible show.
    func showsNeedingRefresh(olderThan interval: TimeInterval, now: Date = .now) -> [MediaItem] {
        let cutoff = now.addingTimeInterval(-interval)
        return tmdbShows().filter { item in
            let eligible = item.status != .watched || item.notificationsEnabled
            guard eligible else { return false }
            guard let refreshed = item.lastRefreshedAt else { return true }
            return refreshed <= cutoff
        }
    }

    /// Every show (TMDB or custom) with reminders switched on.
    func showsWithNotificationsEnabled() -> [MediaItem] {
        let showRaw = MediaKind.show.rawValue
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in
                item.kindRaw == showRaw && item.notificationsEnabled == true
            },
            sortBy: [SortDescriptor(\MediaItem.title)]
        )
        return fetch(descriptor)
    }

    // MARK: Private helpers

    private func tmdbShows() -> [MediaItem] {
        let showRaw = MediaKind.show.rawValue
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate<MediaItem> { item in
                item.kindRaw == showRaw && item.isCustom == false
            },
            sortBy: [SortDescriptor(\MediaItem.updatedAt, order: .reverse)]
        )
        return fetch(descriptor)
    }

    private func fetch(_ descriptor: FetchDescriptor<MediaItem>) -> [MediaItem] {
        do {
            return try context.fetch(descriptor)
        } catch {
            logger.error("Fetch failed: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }

    private func nilIfEmpty(_ string: String?) -> String? {
        guard let string, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return string
    }
}

// MARK: - ShowSnapshot

/// The user-visible fields of a show that a refresh may change.
private struct ShowSnapshot: Equatable {
    let title: String
    let showStatus: String?
    let seasonsData: Data?
    let totalEpisodes: Int?
    let nextEpisodeAirDate: Date?
    let nextEpisodeSeason: Int?
    let nextEpisodeNumber: Int?

    init(item: MediaItem) {
        title = item.title
        showStatus = item.showStatus
        seasonsData = item.seasonsData
        totalEpisodes = item.totalEpisodes
        nextEpisodeAirDate = item.nextEpisodeAirDate
        nextEpisodeSeason = item.nextEpisodeSeason
        nextEpisodeNumber = item.nextEpisodeNumber
    }
}
