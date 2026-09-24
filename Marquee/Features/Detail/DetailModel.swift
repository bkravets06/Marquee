import Foundation
import Observation
import SwiftData
import MarqueeKit

// MARK: - DetailEntry

/// One row of the Details card: a label with either plain text or a link.
struct DetailEntry: Identifiable {

    enum Value {
        case text(String)
        case link(title: String, url: URL)
    }

    let label: String
    let value: Value

    /// Labels are unique within a card, so they double as identifiers.
    var id: String { label }
}

// MARK: - DetailModel

/// State for `MediaDetailView`: the library item (if any), fresh TMDB details
/// and where to watch (if reachable) and the derived values the screen
/// displays, each preferring live details and falling back to what the
/// library has cached.
@MainActor
@Observable
final class DetailModel {

    let reference: MediaReference

    /// The library item, when the title is in the library.
    var item: MediaItem?
    /// List-row form of the title, used to add it to the library.
    var summary: MediaSummary?
    /// Fresh show details from TMDB.
    var show: TVShowDetails?
    /// Fresh movie details from TMDB.
    var movie: MovieDetails?
    /// `true` while a TMDB request is in flight.
    var isLoading = false
    /// Human-readable description of the last failed load, if any.
    var errorMessage: String?
    /// `true` when nothing can be shown because no TMDB credential is configured.
    private(set) var needsCredentials = false
    /// `true` once the library lookup has run at least once.
    private(set) var hasResolvedItem = false

    init(reference: MediaReference) {
        self.reference = reference
    }

    // MARK: Identity

    /// The kind of title. Falls back to the reference's kind before anything loads.
    var kind: MediaKind {
        if let item { return item.kind }
        switch reference {
        case .tmdb(_, let kind):
            return kind
        case .library:
            return .show
        }
    }

    /// TMDB identifier from the item or the reference; `nil` for custom items.
    var tmdbID: Int? {
        if let item { return item.tmdbID }
        if case .tmdb(let id, _) = reference { return id }
        return nil
    }

    var isCustom: Bool { item?.isCustom ?? false }

    var isInLibrary: Bool { item != nil }

    var isLibraryReference: Bool {
        if case .library = reference { return true }
        return false
    }

    /// Anything at all to render (cached item or live details).
    var hasContent: Bool {
        item != nil || show != nil || movie != nil
    }

    /// The reference pointed at a library item that no longer exists.
    var isMissingLibraryItem: Bool {
        isLibraryReference && hasResolvedItem && item == nil
    }

    /// Show redacted placeholders: nothing loaded yet and no failure to report.
    var showsPlaceholder: Bool {
        !hasContent && !isMissingLibraryItem && errorMessage == nil && !needsCredentials
    }

    /// Whether the status menu can do anything (needs an item to update or a summary to add).
    var canChangeStatus: Bool {
        item != nil || summary != nil
    }

    // MARK: Loading

    /// Looks the library item up again (after adding, editing or removing).
    func resolveItem(store: LibraryStore) {
        switch reference {
        case .library(let id):
            item = store.item(id: id)
        case .tmdb(let id, let kind):
            item = store.item(tmdbID: id, kind: kind)
        }
        hasResolvedItem = true
    }

    /// Resolves the library item, then fetches fresh TMDB details and where
    /// the title can be watched when it has a TMDB id and a client is
    /// available. The two requests run concurrently and the page renders as
    /// soon as details arrive. Details are applied to the library item so it
    /// stays current. Errors keep any cached data and surface through
    /// `errorMessage`; a failed watch-provider load only affects its card.
    func load(store: LibraryStore, client: TMDBClient?) async {
        resolveItem(store: store)
        needsCredentials = false

        guard let tmdbID else {
            isLoading = false
            errorMessage = nil
            return
        }

        guard let client else {
            isLoading = false
            if hasContent {
                errorMessage = nil
            } else {
                needsCredentials = true
                errorMessage = TMDBError.missingCredentials.errorDescription
            }
            return
        }

        isLoading = true
        errorMessage = nil
        async let providersLoad: Void = loadWatchProviders(client: client)

        do {
            switch kind {
            case .show:
                let details = try await client.showDetails(id: tmdbID)
                show = details
                summary = details.summary
                if let item {
                    store.apply(details, to: item)
                }
            case .movie:
                let details = try await client.movieDetails(id: tmdbID)
                movie = details
                summary = details.summary
                if let item {
                    store.apply(details, to: item)
                }
            }
        } catch {
            if Task.isCancelled {
                isLoading = false
                return
            }
            errorMessage = DetailModel.message(for: error)
        }

        await providersLoad
        isLoading = false
    }

    /// Persists freshly loaded details onto a newly added library item.
    func applyLoadedDetails(to item: MediaItem, store: LibraryStore) {
        if let show {
            store.apply(show, to: item)
        } else if let movie {
            store.apply(movie, to: item)
        }
    }

    private static func message(for error: Error) -> String {
        if let tmdbError = error as? TMDBError {
            return tmdbError.errorDescription ?? "Something went wrong while talking to TMDB."
        }
        return error.localizedDescription
    }

    // MARK: Where to watch

    /// Where the title can be watched, for every region TMDB lists. `nil` until a load succeeds.
    var watchProviders: WatchProviders?
    /// `true` while the watch-provider request is in flight.
    var isLoadingWatchProviders = false
    /// Human-readable description of the last failed watch-provider load, if any.
    var watchProvidersErrorMessage: String?

    /// `true` for TMDB titles; custom items never show Where to Watch.
    var supportsWatchProviders: Bool { tmdbID != nil && !isCustom }

    /// The offers for `region`, or `nil` when nothing has loaded or TMDB lists nothing there.
    func watchProviders(in region: String) -> RegionWatchProviders? {
        watchProviders?.providers(in: region)
    }

    /// Fetches where the title can be watched. Called by `load` and by the card's inline retry.
    /// Without a TMDB id or a client it leaves the current state alone (no error, not loading).
    func loadWatchProviders(client: TMDBClient?) async {
        guard supportsWatchProviders, let tmdbID, let client else {
            isLoadingWatchProviders = false
            return
        }

        isLoadingWatchProviders = true
        watchProvidersErrorMessage = nil

        do {
            watchProviders = try await client.watchProviders(id: tmdbID, kind: kind)
        } catch {
            // A cancelled request (the screen reloaded or went away) is not a failure.
            if !Task.isCancelled {
                watchProvidersErrorMessage = DetailModel.message(for: error)
            }
        }

        isLoadingWatchProviders = false
    }

    // MARK: Text

    var title: String {
        if let show { return show.name }
        if let movie { return movie.title }
        if let item { return item.title }
        return summary?.title ?? ""
    }

    var tagline: String? {
        let raw = show?.tagline ?? movie?.tagline ?? item?.tagline
        return DetailModel.nonEmpty(raw)
    }

    var overview: String {
        let raw: String
        if let show {
            raw = show.overview
        } else if let movie {
            raw = movie.overview
        } else if let item {
            raw = item.overview
        } else {
            raw = summary?.overview ?? ""
        }
        return raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var year: Int? {
        show?.firstAirDate?.year ?? movie?.releaseDate?.year ?? item?.year ?? summary?.year
    }

    var genres: [String] {
        if let show { return show.genres.map { $0.name } }
        if let movie { return movie.genres.map { $0.name } }
        if let item { return item.genres }
        return summary?.genreNames ?? []
    }

    var voteAverage: Double {
        show?.voteAverage ?? movie?.voteAverage ?? item?.voteAverage ?? summary?.voteAverage ?? 0
    }

    /// Minutes: movie runtime, or a show's typical episode length.
    var runtimeMinutes: Int? {
        movie?.runtime ?? show?.episodeRunTime.first ?? item?.runtimeMinutes
    }

    /// TMDB status ("Returning Series", "Ended", "Released", ...).
    var statusText: String? {
        DetailModel.nonEmpty(show?.status ?? movie?.status ?? item?.showStatus)
    }

    /// "2024 · 3 seasons" for shows, "2024 · 2h 46m" for movies. Rating is rendered separately.
    var metadataText: String {
        var parts: [String] = []
        if let year {
            parts.append(String(year))
        }
        switch kind {
        case .show:
            let count = seasonCount
            if count > 0 {
                parts.append(count == 1 ? "1 season" : "\(count) seasons")
            } else if let total = episodeTotal, total > 0 {
                parts.append(total == 1 ? "1 episode" : "\(total) episodes")
            }
        case .movie:
            if let minutes = runtimeMinutes, minutes > 0 {
                parts.append(Formatters.runtime(minutes: minutes))
            }
        }
        return parts.joined(separator: " · ")
    }

    // MARK: Images

    var backdropURL: URL? {
        let path = show?.backdropPath ?? movie?.backdropPath ?? item?.backdropPath ?? summary?.backdropPath
        return TMDBImage.backdrop(path, size: .w1280)
    }

    var posterURL: URL? {
        let path = show?.posterPath ?? movie?.posterPath ?? item?.posterPath ?? summary?.posterPath
        return TMDBImage.poster(path, size: .w342)
    }

    /// User-supplied poster for custom items.
    var posterData: Data? {
        item?.customPosterData
    }

    // MARK: Episodes

    /// Regular seasons (number >= 1), preferring live details.
    var regularSeasons: [SeasonInfo] {
        let all: [SeasonInfo]
        if let show {
            all = show.seasonInfos
        } else if let item {
            all = item.seasons
        } else {
            all = []
        }
        return all.filter { $0.number >= 1 }.sorted { $0.number < $1.number }
    }

    var seasonCount: Int {
        if let show, show.numberOfSeasons > 0 {
            return show.numberOfSeasons
        }
        return regularSeasons.count
    }

    var episodeTotal: Int? {
        if let show, show.numberOfEpisodes > 0 {
            return show.numberOfEpisodes
        }
        return item?.episodeTotal
    }

    /// The next episode to air, from live details or the cached item fields.
    var nextEpisode: EpisodeSummary? {
        guard kind == .show else { return nil }
        if let show {
            return show.nextEpisodeToAir
        }
        guard let item, let pointer = item.nextEpisodePointer else { return nil }
        let airDate: CivilDate? = item.nextEpisodeAirDate.map { CivilDate($0) }
        return EpisodeSummary(
            id: 0,
            name: item.nextEpisodeName ?? "",
            overview: "",
            seasonNumber: pointer.season,
            episodeNumber: pointer.episode,
            airDate: airDate
        )
    }

    // MARK: Links

    /// https://www.themoviedb.org/tv/<id> or /movie/<id>.
    var tmdbURL: URL? {
        guard let tmdbID else { return nil }
        let segment = kind == .show ? "tv" : "movie"
        return URL(string: "https://www.themoviedb.org/\(segment)/\(tmdbID)")
    }

    var homepageURL: URL? {
        guard let raw = DetailModel.nonEmpty(show?.homepage ?? movie?.homepage),
              let url = URL(string: raw),
              url.scheme != nil else {
            return nil
        }
        return url
    }

    // MARK: Details card

    var languageName: String? {
        guard let code = DetailModel.nonEmpty(show?.originalLanguage ?? movie?.originalLanguage ?? summary?.originalLanguage) else {
            return nil
        }
        return Locale.current.localizedString(forLanguageCode: code) ?? code.uppercased()
    }

    /// Rows for the Details card, in display order.
    var detailEntries: [DetailEntry] {
        var entries: [DetailEntry] = []

        if let status = statusText {
            entries.append(DetailEntry(label: "Status", value: .text(status)))
        }

        switch kind {
        case .show:
            appendShowEntries(to: &entries)
        case .movie:
            appendMovieEntries(to: &entries)
        }

        if let minutes = runtimeMinutes, minutes > 0 {
            let label = kind == .show ? "Episode Length" : "Runtime"
            entries.append(DetailEntry(label: label, value: .text(Formatters.runtime(minutes: minutes))))
        }
        if let language = languageName {
            entries.append(DetailEntry(label: "Language", value: .text(language)))
        }
        appendLibraryEntries(to: &entries)
        appendLinkEntries(to: &entries)
        return entries
    }

    private func appendShowEntries(to entries: inout [DetailEntry]) {
        if let first = show?.firstAirDate?.startOfDay() ?? item?.releaseDate {
            entries.append(DetailEntry(label: "First Aired", value: .text(Formatters.shortDate(first))))
        }
        if let last = show?.lastAirDate?.startOfDay() {
            entries.append(DetailEntry(label: "Last Aired", value: .text(Formatters.shortDate(last))))
        }
        if let show, !show.networks.isEmpty {
            let label = show.networks.count == 1 ? "Network" : "Networks"
            let names = show.networks.map { $0.name }.joined(separator: ", ")
            entries.append(DetailEntry(label: label, value: .text(names)))
        }
        if let type = DetailModel.nonEmpty(show?.type) {
            entries.append(DetailEntry(label: "Type", value: .text(type)))
        }
        if let total = episodeTotal, total > 0 {
            entries.append(DetailEntry(label: "Episodes", value: .text(String(total))))
        }
    }

    private func appendMovieEntries(to entries: inout [DetailEntry]) {
        if let release = movie?.releaseDate?.startOfDay() ?? item?.releaseDate {
            entries.append(DetailEntry(label: "Released", value: .text(Formatters.shortDate(release))))
        }
    }

    private func appendLibraryEntries(to entries: inout [DetailEntry]) {
        guard let item else { return }
        if item.isCustom, item.isShow {
            let reminders = item.notificationsEnabled ? (item.releaseSchedule.map { $0.summary() } ?? "Off") : "Off"
            entries.append(DetailEntry(label: "Reminders", value: .text(reminders)))
        }
        if item.status == .watched, let finished = item.finishedAt {
            entries.append(DetailEntry(label: "Watched", value: .text(Formatters.shortDate(finished))))
        }
        entries.append(DetailEntry(label: "Added", value: .text(Formatters.shortDate(item.addedAt))))
    }

    private func appendLinkEntries(to entries: inout [DetailEntry]) {
        if let url = tmdbURL {
            entries.append(DetailEntry(label: "TMDB", value: .link(title: "View on TMDB", url: url)))
        }
        if let url = homepageURL {
            entries.append(DetailEntry(label: "Website", value: .link(title: url.host() ?? "Official Site", url: url)))
        }
        if let url = item?.linkURL {
            entries.append(DetailEntry(label: "Link", value: .link(title: url.host() ?? url.absoluteString, url: url)))
        }
    }

    // MARK: Helpers

    private static func nonEmpty(_ string: String?) -> String? {
        guard let string else { return nil }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
