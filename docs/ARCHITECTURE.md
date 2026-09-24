# Marquee — Architecture & Implementation Spec

Marquee is a native iOS app for tracking the shows and movies you are watching.
It is written in Swift + SwiftUI, persists with SwiftData, uses TMDB (The Movie
Database) as its public catalog API, and schedules **local** notifications for
new episodes. The design goal is "what Apple would ship": system components,
system typography, semantic colors, large titles, inset-grouped lists,
`ContentUnavailableView` empty states, SF Symbols, haptics, Dynamic Type, and
full dark mode. When compiled with Xcode 26 the native controls adopt Liquid
Glass automatically; no custom chrome is used.

This document is the **contract** between the modules. Names, signatures and
file locations below are normative. If you must deviate, update this file in the
same change.

---

## 1. Targets & layout

```
Marquee.xcodeproj/                 Xcode 16+ project (synchronized folders, objectVersion 77)
  project.pbxproj
  xcshareddata/xcschemes/Marquee.xcscheme
Marquee/                           iOS app target "Marquee" (bundle id com.bjkravets.marquee)
  MarqueeApp.swift                 @main
  AppDelegate.swift                UNUserNotificationCenterDelegate + BGTask registration
  Info.plist                       background modes, BGTask identifiers (merged with generated plist)
  Assets.xcassets/                 AppIcon, AccentColor
  Support/                         AppEnvironment, AppSettings, Keychain, Navigator, Formatters, ImageCache
  Models/                          MediaItem (@Model), MediaItem+Convenience, LibraryStore, PreviewData
  Services/                        NotificationManager, LibraryRefresher, BackgroundRefresh
  Components/                      PosterView, BackdropHeader, StatusMenu, KindBadge, RatingLabel, GenreChips, MediaCard, ProgressBadge
  Features/
    Root/                          RootView, OnboardingView
    Discover/                      DiscoverView, DiscoverModel, MediaCarousel, SeeAllView
    Library/                       LibraryView, LibraryRow, UpNextStrip
    Detail/                        MediaDetailView, DetailModel, SeasonsView, EpisodeListView, EpisodeRow
    Search/                        SearchView, SearchModel
    Custom/                        CustomItemForm
    Settings/                      SettingsView, TokenEntryView
MarqueeTests/                      iOS unit test target (XCTest) for the app: LibraryStore, MediaItem, NotificationManager planning
MarqueeKit/                        Local Swift package (pure Swift + Foundation; builds on Linux)
  Package.swift
  Sources/MarqueeKit/
    Domain/                        MediaKind, WatchStatus, EpisodePointer, SeasonInfo, NextUp, ReleaseSchedule, CivilDate, EpisodeReminder
    TMDB/                          TMDBClient, TMDBEndpoint, TMDBError, TMDBImage, TMDBGenres, DTOs (public) + RawDTOs (internal)
  Tests/MarqueeKitTests/
    Fixtures/*.json                real-shaped TMDB responses
    *.swift                        XCTest: decoding, request building, NextUp, ReleaseSchedule, CivilDate, EpisodeReminder
.github/workflows/ci.yml           macOS runner: swift test (package) + xcodebuild build/test (app)
docs/ARCHITECTURE.md               this file
README.md, CLAUDE.md, .gitignore
```

Build settings (app): `IPHONEOS_DEPLOYMENT_TARGET = 18.0`, `SWIFT_VERSION = 5.0`
(Swift 5 language mode, `SWIFT_STRICT_CONCURRENCY = minimal`), iPhone + iPad
(`TARGETED_DEVICE_FAMILY = 1,2`), portrait + landscape on iPad, portrait on
iPhone. `GENERATE_INFOPLIST_FILE = YES` with `INFOPLIST_FILE = Marquee/Info.plist`
supplying the extra keys. No entitlements file is needed (local notifications
and background fetch need only Info.plist keys).

Package: `swift-tools-version: 5.9`, `swiftLanguageVersions: [.v5]`,
platforms `.iOS(.v18), .macOS(.v14)`. **No UIKit/SwiftUI/SwiftData imports in
MarqueeKit.** Use `#if canImport(FoundationNetworking) import FoundationNetworking #endif`
wherever `URLSession`/`URLRequest` are used so it compiles on Linux.

---

## 2. MarqueeKit — public API (normative)

### 2.1 Domain

```swift
public enum MediaKind: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case show, movie
    public var id: String { rawValue }
    public var displayName: String        // "Show" / "Movie"
    public var pluralDisplayName: String  // "Shows" / "Movies"
    public var symbolName: String         // "tv" / "film"
}

public enum WatchStatus: String, Codable, Sendable, CaseIterable, Identifiable, Hashable {
    case watching, watchlist, watched
    public var id: String { rawValue }
    public var displayName: String  // "Watching", "Watchlist", "Watched"
    public var symbolName: String   // "play.circle", "bookmark", "checkmark.circle"
}

/// "Last watched" pointer. (0,0) means not started. Specials (season 0) are ignored by NextUp.
public struct EpisodePointer: Hashable, Comparable, Codable, Sendable {
    public var season: Int
    public var episode: Int
    public init(season: Int, episode: Int)
    public static let notStarted: EpisodePointer   // (0, 0)
    public var isStarted: Bool                     // != notStarted
    public var label: String                       // "S2 E5"
    // Comparable: by season, then episode
}

public struct SeasonInfo: Hashable, Codable, Sendable, Identifiable {
    public var number: Int
    public var name: String
    public var episodeCount: Int
    public var airDate: CivilDate?
    public var posterPath: String?
    public var id: Int { number }
    public init(number: Int, name: String, episodeCount: Int, airDate: CivilDate? = nil, posterPath: String? = nil)
}

public enum NextUp {
    /// Next unwatched episode after `pointer`, walking `seasons` (season 0 ignored, seasons sorted by number,
    /// seasons with episodeCount == 0 skipped). Returns nil when caught up (or no seasons).
    public static func next(after pointer: EpisodePointer, in seasons: [SeasonInfo]) -> EpisodePointer?
    /// Total number of regular episodes (season >= 1).
    public static func totalEpisodes(in seasons: [SeasonInfo]) -> Int
    /// Number of regular episodes at or before `pointer` (progress numerator).
    public static func watchedCount(upTo pointer: EpisodePointer, in seasons: [SeasonInfo]) -> Int
    /// The pointer immediately before `pointer` (for "mark unwatched"); `.notStarted` if none.
    public static func previous(before pointer: EpisodePointer, in seasons: [SeasonInfo]) -> EpisodePointer
}

/// Calendar date without time zone (TMDB "YYYY-MM-DD").
public struct CivilDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int, month: Int, day: Int
    public init(year: Int, month: Int, day: Int)
    public init?(_ string: String)                                  // "2026-09-30"; empty/invalid -> nil
    public init(_ date: Date, calendar: Calendar = .current)
    public static func today(calendar: Calendar = .current) -> CivilDate
    public var string: String                                       // "2026-09-30"
    public var description: String { string }
    public func date(in calendar: Calendar = .current, hour: Int = 0, minute: Int = 0) -> Date?
    public func startOfDay(in calendar: Calendar = .current) -> Date? // == date(hour:0,minute:0)
    // Codable: encodes/decodes as the "YYYY-MM-DD" string. Decoding "" or an unparsable string throws;
    // DTOs therefore decode it via `decodeIfPresent` through a lenient helper (see 2.2) so "" becomes nil.
}

/// Weekly release cadence for custom shows.
public struct ReleaseSchedule: Hashable, Codable, Sendable {
    public var weekday: Int   // 1 = Sunday ... 7 = Saturday (Calendar convention)
    public var hour: Int      // 0...23
    public var minute: Int    // 0...59
    public init(weekday: Int, hour: Int, minute: Int)
    public var dateComponents: DateComponents                     // weekday/hour/minute, for a repeating calendar trigger
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date?
    public func summary(calendar: Calendar = .current) -> String  // "Tuesdays at 8:00 PM"
}

/// Pure planning for episode reminders (used by the app's NotificationManager; tested in the package).
public enum EpisodeReminder {
    public static let identifierPrefix = "marquee.episode."
    public static let customIdentifierPrefix = "marquee.custom."
    public static func identifier(itemID: String, pointer: EpisodePointer) -> String    // "marquee.episode.<id>.S2E5"
    public static func customIdentifier(itemID: String) -> String                       // "marquee.custom.<id>"
    /// Fire components for an episode airing on `airDate` at the user's preferred time. Nil if that moment is already past `now`.
    public static func fireComponents(airDate: CivilDate, hour: Int, minute: Int, now: Date, calendar: Calendar = .current) -> DateComponents?
    public static func title(showTitle: String) -> String                               // "New episode of <show>"
    public static func body(pointer: EpisodePointer, episodeName: String?) -> String    // "S2 E5 “Name” is out today." / "S2 E5 is out today."
}
```

### 2.2 TMDB types

All dates in DTOs are `CivilDate?`, decoded leniently (missing, null, "" and
unparsable all become `nil`). Image paths are the raw TMDB paths ("/abc.jpg").

```swift
public struct MediaSummary: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var kind: MediaKind
    public var title: String
    public var overview: String
    public var posterPath: String?
    public var backdropPath: String?
    public var releaseDate: CivilDate?     // first_air_date for shows, release_date for movies
    public var voteAverage: Double
    public var voteCount: Int
    public var popularity: Double
    public var genreIDs: [Int]
    public var originalLanguage: String?
    public init(id:kind:title:overview:posterPath:backdropPath:releaseDate:voteAverage:voteCount:popularity:genreIDs:originalLanguage:)
    public var year: Int?
    public var genreNames: [String]        // via TMDBGenres, in order, unknown ids dropped
}
// Hashable/Identifiable note: two summaries with the same TMDB id but different kinds are different items;
// give `MediaSummary` a `public var key: String { "\(kind.rawValue)-\(id)" }` and use `key` for ForEach ids
// where lists mix kinds (trending/all, multi search).

public struct PagedResponse<Item: Codable & Sendable>: Codable, Sendable {
    public var page: Int
    public var results: [Item]
    public var totalPages: Int
    public var totalResults: Int
}

public struct Genre: Hashable, Codable, Sendable, Identifiable { public var id: Int; public var name: String }
public struct Network: Hashable, Codable, Sendable, Identifiable { public var id: Int; public var name: String; public var logoPath: String? }

public struct EpisodeSummary: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var overview: String
    public var seasonNumber: Int
    public var episodeNumber: Int
    public var airDate: CivilDate?
    public var stillPath: String?
    public var runtime: Int?
    public var voteAverage: Double?
    public var pointer: EpisodePointer
    public func hasAired(asOf today: CivilDate) -> Bool     // airDate != nil && airDate <= today
}

public struct TVSeasonSummary: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var seasonNumber: Int
    public var name: String
    public var overview: String
    public var episodeCount: Int
    public var airDate: CivilDate?
    public var posterPath: String?
    public var info: SeasonInfo
}

public struct TVShowDetails: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var name: String
    public var overview: String
    public var tagline: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var firstAirDate: CivilDate?
    public var lastAirDate: CivilDate?
    public var genres: [Genre]
    public var status: String?             // "Returning Series", "Ended", "Canceled", "In Production"
    public var type: String?               // "Scripted", "Reality", ...
    public var numberOfSeasons: Int
    public var numberOfEpisodes: Int
    public var episodeRunTime: [Int]
    public var seasons: [TVSeasonSummary]
    public var nextEpisodeToAir: EpisodeSummary?
    public var lastEpisodeToAir: EpisodeSummary?
    public var networks: [Network]
    public var voteAverage: Double
    public var voteCount: Int
    public var inProduction: Bool
    public var homepage: String?
    public var originalLanguage: String?
    public var summary: MediaSummary
    public var seasonInfos: [SeasonInfo]   // regular seasons (number >= 1) sorted ascending; specials excluded
}

public struct SeasonDetails: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var seasonNumber: Int
    public var name: String
    public var overview: String
    public var airDate: CivilDate?
    public var posterPath: String?
    public var episodes: [EpisodeSummary]
}

public struct MovieDetails: Hashable, Codable, Sendable, Identifiable {
    public var id: Int
    public var title: String
    public var overview: String
    public var tagline: String?
    public var posterPath: String?
    public var backdropPath: String?
    public var releaseDate: CivilDate?
    public var runtime: Int?
    public var genres: [Genre]
    public var status: String?             // "Released", "Post Production", ...
    public var voteAverage: Double
    public var voteCount: Int
    public var homepage: String?
    public var originalLanguage: String?
    public var imdbID: String?
    public var summary: MediaSummary
}

public enum TrendingScope: String, Sendable { case all, tv, movie }
public enum TrendingWindow: String, Sendable { case day, week }

public enum TMDBError: Error, LocalizedError, Sendable, Equatable {
    case missingCredentials
    case unauthorized                    // 401
    case notFound                        // 404
    case rateLimited(retryAfter: Int?)   // 429
    case http(status: Int, message: String?)
    case decoding(String)
    case network(String)
    public var errorDescription: String? // human readable, e.g. "Your TMDB API key was rejected."
}

public enum TMDBImage {
    public enum PosterSize: String, Sendable { case w92, w154, w185, w342, w500, w780, original }
    public enum BackdropSize: String, Sendable { case w300, w780, w1280, original }
    public enum StillSize: String, Sendable { case w92, w185, w300, original }
    public static let baseURL = URL(string: "https://image.tmdb.org/t/p/")!
    public static func poster(_ path: String?, size: PosterSize = .w342) -> URL?
    public static func backdrop(_ path: String?, size: BackdropSize = .w780) -> URL?
    public static func still(_ path: String?, size: StillSize = .w300) -> URL?
    public static func url(path: String?, size: String) -> URL?
}

public enum TMDBGenres {
    public static let tv: [Int: String]      // official TMDB TV genre list (10759 Action & Adventure, 16 Animation, 35 Comedy, 80 Crime, 99 Documentary, 18 Drama, 10751 Family, 10762 Kids, 9648 Mystery, 10763 News, 10764 Reality, 10765 Sci-Fi & Fantasy, 10766 Soap, 10767 Talk, 10768 War & Politics, 37 Western)
    public static let movie: [Int: String]   // official TMDB movie genre list (28 Action, 12 Adventure, 16 Animation, 35 Comedy, 80 Crime, 99 Documentary, 18 Drama, 10751 Family, 14 Fantasy, 36 History, 27 Horror, 10402 Music, 9648 Mystery, 10749 Romance, 878 Science Fiction, 10770 TV Movie, 53 Thriller, 10752 War, 37 Western)
    public static func name(for id: Int, kind: MediaKind) -> String?
    public static func name(for id: Int) -> String?    // tv first, then movie
}

/// Credentials: either a TMDB v4 "API Read Access Token" (long JWT, contains ".") sent as
/// `Authorization: Bearer <token>`, or a v3 API key (32 hex chars) sent as `api_key` query item.
/// `TMDBCredential.detect(_:)` picks based on shape.
public enum TMDBCredential: Hashable, Sendable {
    case bearer(String)
    case apiKey(String)
    public static func detect(_ raw: String) -> TMDBCredential?   // trims whitespace; nil if empty
}

public actor TMDBClient {
    public static let baseURL = URL(string: "https://api.themoviedb.org/3")!
    public init(credential: TMDBCredential, session: URLSession = .shared, language: String = "en-US", region: String? = Locale.current.region?.identifier, baseURL: URL = TMDBClient.baseURL)
    public func validateCredentials() async throws -> Bool          // GET /authentication -> success
    public func trending(_ scope: TrendingScope = .all, window: TrendingWindow = .day, page: Int = 1) async throws -> PagedResponse<MediaSummary>
    public func airingToday(page: Int = 1) async throws -> PagedResponse<MediaSummary>      // GET /tv/airing_today
    public func onTheAir(page: Int = 1) async throws -> PagedResponse<MediaSummary>         // GET /tv/on_the_air
    public func popularShows(page: Int = 1) async throws -> PagedResponse<MediaSummary>     // GET /tv/popular
    public func topRatedShows(page: Int = 1) async throws -> PagedResponse<MediaSummary>    // GET /tv/top_rated
    public func nowPlayingMovies(page: Int = 1) async throws -> PagedResponse<MediaSummary> // GET /movie/now_playing (region)
    public func upcomingMovies(page: Int = 1) async throws -> PagedResponse<MediaSummary>   // GET /movie/upcoming (region)
    public func popularMovies(page: Int = 1) async throws -> PagedResponse<MediaSummary>    // GET /movie/popular
    public func topRatedMovies(page: Int = 1) async throws -> PagedResponse<MediaSummary>   // GET /movie/top_rated
    public func search(_ query: String, kind: MediaKind? = nil, page: Int = 1) async throws -> PagedResponse<MediaSummary>
        // nil -> GET /search/multi (person results dropped, totalResults left as reported); .show -> /search/tv; .movie -> /search/movie; include_adult=false
    public func showDetails(id: Int) async throws -> TVShowDetails         // GET /tv/{id}
    public func season(showID: Int, number: Int) async throws -> SeasonDetails   // GET /tv/{id}/season/{n}
    public func movieDetails(id: Int) async throws -> MovieDetails         // GET /movie/{id}
}
```

Implementation notes for the client:
* Build requests through an internal `TMDBEndpoint` (path + query items) and an
  internal `makeRequest(_:)` so tests can assert URL/query/header construction
  without network. Always add `language`; add `region` to now_playing/upcoming
  (and `include_adult=false` to search).
* Decode with a `JSONDecoder` using `.convertFromSnakeCase` **or** explicit
  `CodingKeys` — pick one and be consistent. Raw list rows are internal structs
  (`RawTVResult`, `RawMovieResult`, `RawMultiResult` with `mediaType`) mapped to
  `MediaSummary`. `nil`/missing `overview` becomes `""`; missing vote fields
  become 0.
* Map status codes: 401 → `.unauthorized`, 404 → `.notFound`, 429 →
  `.rateLimited(retryAfter:)` (parse `Retry-After`), other non-2xx →
  `.http(status:message:)` using TMDB's `status_message` if present.
  `URLError` → `.network(localizedDescription)`. `DecodingError` → `.decoding(...)`.
* Use `try await session.data(for: request)`; it exists on Linux Foundation too.

### 2.3 Tests (package)

Fixtures live in `Tests/MarqueeKitTests/Fixtures` and are declared as
`resources: [.copy("Fixtures")]`; load with `Bundle.module`. Required fixtures:
`trending_all_day.json` (mix of tv, movie and one person), `search_multi.json`,
`tv_airing_today.json`, `movie_now_playing.json`, `tv_details.json` (with
`next_episode_to_air`, `last_episode_to_air`, seasons including a season 0),
`tv_season.json`, `movie_details.json`, `error_401.json`. Tests cover decoding of
each, `CivilDate` parsing (incl. "" → nil), `NextUp` (not started, mid-season,
season rollover, caught up, specials skipped, empty seasons skipped),
`ReleaseSchedule.nextOccurrence`, `EpisodeReminder.fireComponents` (past →
nil), request building (paths, `Bearer` header vs `api_key` query, language,
region), and error mapping using a `URLProtocol` stub.

---

## 3. App — persistence

### 3.1 `MediaItem` (SwiftData, `Marquee/Models/MediaItem.swift`)

```swift
import SwiftData
import MarqueeKit

@Model
final class MediaItem {
    @Attribute(.unique) var id: UUID
    var tmdbID: Int?                 // nil for custom items
    var kindRaw: String              // MediaKind.rawValue
    var statusRaw: String            // WatchStatus.rawValue
    var title: String
    var overview: String
    var tagline: String?
    var posterPath: String?          // TMDB path
    var backdropPath: String?
    @Attribute(.externalStorage) var customPosterData: Data?   // JPEG, <= 600px on the long side
    var releaseDate: Date?           // local start of day
    var genres: [String]
    var runtimeMinutes: Int?
    var voteAverage: Double?
    var showStatus: String?          // TMDB status string for shows
    var seasonsData: Data?           // JSON-encoded [SeasonInfo]  (regular seasons only)
    var totalEpisodes: Int?          // TMDB numberOfEpisodes, or user-entered for custom shows
    var progressSeason: Int          // last watched pointer; 0/0 = not started
    var progressEpisode: Int
    var notificationsEnabled: Bool
    var nextEpisodeAirDate: Date?    // local start of day
    var nextEpisodeSeason: Int?
    var nextEpisodeNumber: Int?
    var nextEpisodeName: String?
    var releaseScheduleData: Data?   // JSON-encoded ReleaseSchedule (custom shows)
    var isCustom: Bool
    var linkURL: URL?
    var notes: String
    var userRating: Int?             // 1...5, optional
    var addedAt: Date
    var updatedAt: Date
    var lastWatchedAt: Date?
    var finishedAt: Date?
    var lastRefreshedAt: Date?

    init(kind: MediaKind, status: WatchStatus, title: String, ...)   // sensible defaults; id = UUID(); addedAt = updatedAt = .now
}
```

`MediaItem+Convenience.swift` adds (computed, not persisted):
`kind: MediaKind`, `status: WatchStatus` (get/set on the raw strings),
`seasons: [SeasonInfo]` (get/set via `seasonsData`), `releaseSchedule:
ReleaseSchedule?` (via data), `progress: EpisodePointer` (get/set),
`nextUp: EpisodePointer?` (NextUp over `seasons`; for custom shows without
seasons: `EpisodePointer(season: max(progress.season,1), episode: progress.episode + 1)`
unless `totalEpisodes` is set and reached), `nextEpisodePointer: EpisodePointer?`,
`isShow`, `isMovie`, `year: Int?`, `posterURL(size:)`, `backdropURL(size:)`,
`watchedEpisodeCount`, `episodeTotal: Int?`, `progressFraction: Double?`,
`airsWithinDays(_:) -> Bool`, `nextEpisodeLabel: String?` ("S3 E4 · Thu").

### 3.2 `LibraryStore` (`Marquee/Models/LibraryStore.swift`)

```swift
@MainActor
struct LibraryStore {
    let context: ModelContext
    init(context: ModelContext)

    func item(id: UUID) -> MediaItem?
    func item(tmdbID: Int, kind: MediaKind) -> MediaItem?
    func allItems() -> [MediaItem]
    func items(status: WatchStatus) -> [MediaItem]
    func status(of summary: MediaSummary) -> WatchStatus?

    @discardableResult func add(_ summary: MediaSummary, status: WatchStatus) -> MediaItem  // idempotent; existing item -> setStatus
    @discardableResult func addCustom(title: String, kind: MediaKind, status: WatchStatus, overview: String, posterData: Data?, linkURL: URL?, notes: String, totalEpisodes: Int?, schedule: ReleaseSchedule?, notificationsEnabled: Bool) -> MediaItem

    func apply(_ details: TVShowDetails, to item: MediaItem)   // metadata, seasons, totalEpisodes, showStatus, next episode fields, lastRefreshedAt
    func apply(_ details: MovieDetails, to item: MediaItem)

    func setStatus(_ item: MediaItem, to status: WatchStatus)   // watched: finishedAt = now, lastWatchedAt = now; watching from watched clears finishedAt
    func setProgress(_ item: MediaItem, to pointer: EpisodePointer)  // updates lastWatchedAt, updatedAt; if status == .watchlist -> .watching
    func markNextEpisodeWatched(_ item: MediaItem)               // uses item.nextUp; no-op when caught up
    func markPreviousEpisodeUnwatched(_ item: MediaItem)
    func markMovieWatched(_ item: MediaItem)                     // setStatus(.watched)
    func setNotifications(_ item: MediaItem, enabled: Bool)
    func delete(_ item: MediaItem)
    func deleteAll()
    func save()                                                  // try? context.save()

    func showsNeedingRefresh(olderThan interval: TimeInterval, now: Date = .now) -> [MediaItem]  // TMDB shows in watching/watchlist or with notifications on
    func showsWithNotificationsEnabled() -> [MediaItem]
}
```

All mutations set `updatedAt = .now` and call `save()`.

### 3.3 `PreviewData`

`enum PreviewData { @MainActor static let container: ModelContainer  // in-memory, pre-populated
                    static func sampleItems() -> [MediaItem]; static let sampleSummary: MediaSummary; static let sampleShowDetails ... }`
Used by `#Preview` blocks and tests.

---

## 4. App — support & services

* `AppEnvironment` (`@MainActor @Observable final class`, injected via
  `.environment(...)`): `var client: TMDBClient?`, `let settings: AppSettings`,
  `let notifications: NotificationManager`, `var hasCredentials: Bool`,
  `func setCredential(_ raw: String) throws` (validates shape, saves to
  Keychain, rebuilds client), `func clearCredential()`,
  `func makeClient()` (Keychain, else in DEBUG `ProcessInfo` env
  `TMDB_ACCESS_TOKEN`). Region/language from `settings`.
* `AppSettings` (`@Observable`, UserDefaults-backed): `hasCompletedOnboarding: Bool`,
  `reminderHour: Int` (default 9), `reminderMinute: Int` (0),
  `region: String` (default `Locale.current.region?.identifier ?? "US"`),
  `lastLibraryRefresh: Date?`, `reminderTime: Date` (get/set convenience for a
  `DatePicker`).
* `Keychain`: `enum Keychain { static func string(for key: String) -> String?; static func set(_ value: String, for key: String) throws; static func delete(_ key: String) }` (Security framework, `kSecClassGenericPassword`, service `com.bjkravets.marquee`).
* `Navigator` (`@MainActor @Observable final class`): `var tab: AppTab` (`enum AppTab: Hashable { case discover, library, search }`), `var libraryPath: [LibraryRoute]`, `var pendingItemID: UUID?`, `func open(itemID:)`. `enum LibraryRoute: Hashable { case item(UUID) }`.
* `Formatters`: runtime ("1h 42m"), year, `relativeAirDate(Date) -> String` ("Today", "Tomorrow", "Thu", "Oct 3"), `Date` helpers.
* `ImageCache.configure()` sets `URLCache.shared` to 64 MB memory / 256 MB disk. Called at launch.
* `NotificationManager` (`@MainActor @Observable final class`):
  `var authorizationStatus: UNAuthorizationStatus`, `func refreshAuthorizationStatus() async`,
  `func requestAuthorization() async -> Bool`,
  `func sync(items: [MediaItem], settings: AppSettings) async` — builds the
  desired set of `UNNotificationRequest`s (one per TMDB show with
  `notificationsEnabled` and a future `nextEpisodeAirDate`, via
  `EpisodeReminder`; one repeating request per custom show with
  `notificationsEnabled` and a `releaseSchedule`), removes pending Marquee
  requests that are no longer desired, adds missing ones. `userInfo["itemID"] = item.id.uuidString`.
  `func cancel(for item: MediaItem)`, `func pendingCount() async -> Int`.
* `LibraryRefresher` (`@MainActor`): `init(environment:, context:)`,
  `func refreshAll(force: Bool) async` — for `showsNeedingRefresh(olderThan: 6h)`
  fetch `showDetails`, `store.apply`, then `notifications.sync`. Records
  `settings.lastLibraryRefresh`. Swallows per-item errors, stops on `.unauthorized`.
* `BackgroundRefresh`: `static let taskIdentifier = "com.bjkravets.marquee.refresh"`,
  `static func register(container:environment:)` (BGTaskScheduler.register — must
  be called from `application(_:didFinishLaunchingWithOptions:)`),
  `static func schedule()` (BGAppRefreshTaskRequest earliest 6h), handler runs
  `LibraryRefresher.refreshAll(force: false)` then reschedules.
* `AppDelegate` (`UIApplicationDelegate`, `UNUserNotificationCenterDelegate`):
  sets `UNUserNotificationCenter.current().delegate = self`, registers the BG
  task, shows banners in foreground (`.banner, .sound, .list`), and on tap sets
  `Navigator.shared.open(itemID:)`. `MarqueeApp` uses
  `@UIApplicationDelegateAdaptor`. Shared instances: `AppEnvironment.shared`,
  `Navigator.shared`, `ModelContainer` created once in `MarqueeApp` via a
  static `AppModelContainer.shared` (schema `[MediaItem.self]`,
  `isStoredInMemoryOnly` false, falls back to in-memory if the store fails to
  open).

Info.plist keys: `UIBackgroundModes = [fetch]`,
`BGTaskSchedulerPermittedIdentifiers = [com.bjkravets.marquee.refresh]`,
`ITSAppUsesNonExemptEncryption = false`. Photos picker needs no usage string.

---

## 5. App — UI spec

Global: `RootView` = `TabView(selection:)` using the iOS 18 `Tab` API with
`Tab("Discover", systemImage: "sparkles", value: .discover)`,
`Tab("Library", systemImage: "rectangle.stack", value: .library)`,
`Tab(value: .search, role: .search)`. Each tab has its own `NavigationStack`.
Onboarding is a full-screen cover on first launch. Settings is a sheet opened
from a `gearshape` toolbar button on Discover and Library. Accent color:
"Marquee Gold" (light `#F5A623`, dark `#FFB84D`). Posters use
`RoundedRectangle(cornerRadius: 10, style: .continuous)` with a subtle
shadow; placeholder is a `secondary` system fill with the kind's SF Symbol.
All lists use system styles; no custom nav/tab chrome. Every screen has a
`#Preview` using `PreviewData`.

**Discover** — Large title "Discover". If no credentials: `ContentUnavailableView`
("Connect to TMDB", `key.fill`, button opens Settings). Otherwise vertical
`ScrollView` of `MediaCarousel` sections, each with a header (title + "See All"
`NavigationLink` to `SeeAllView` grid that pages): Trending Today (all),
Airing Today (shows), On the Air This Week (shows), In Theaters (movies),
Coming Soon (movies), Popular Shows, Popular Movies. Cards: 120pt poster,
title (2 lines), caption (year · kind). Context menu on card: Add to
Watchlist / Start Watching / Mark Watched. Tap → `MediaDetailView(.tmdb(id, kind))`.
Pull to refresh. Sections load independently (each `.task`) and show
redacted placeholders while loading; a failing section shows an inline retry.

**Library** — Large title "Library". Segmented `Picker` (Watching / Watchlist /
Watched) in the top of the list (`.pickerStyle(.segmented)`), toolbar: filter
menu (All/Shows/Movies), sort menu (Recently updated / Title / Date added),
`plus` menu ("Add Custom Show…", "Add Custom Movie…"), `gearshape`. Watching
segment shows an "Up Next" horizontal strip (`UpNextStrip`) of shows whose next
episode airs within 7 days ("Thu · S3 E4"). Rows (`LibraryRow`): 56×84 poster,
title, subtitle (shows: "S2 E5 · 12 of 24" + next-air relative date; movies:
year · runtime), trailing circular button: shows → mark next episode watched
(`checkmark.circle`), movies → mark watched. Swipe leading: mark next watched;
swipe trailing: Delete (destructive), Watchlist/Watched moves. Context menu:
status options, Notifications toggle (shows), Edit (custom), Delete. Empty
states per segment with a "Discover" / "Search" button. Tap → `MediaDetailView(.library(id))`.
`NavigationStack(path: $navigator.libraryPath)` and `.navigationDestination(for: LibraryRoute.self)`.

**Detail** — `MediaDetailView(reference: MediaReference)` with
`enum MediaReference: Hashable { case tmdb(id: Int, kind: MediaKind); case library(UUID) }`.
`DetailModel` resolves: library item (if any) + fresh TMDB details when a
`tmdbID` exists (and calls `store.apply` to keep the item fresh). Layout: hero
backdrop (16:9, gradient into background, `.ignoresSafeArea(edges: .top)`),
poster + title block (title `.largeTitle.bold()`, tagline, metadata line "2024 ·
3 seasons · TV-MA-free, just year · seasons/runtime · ★ 8.1"), genre chips,
action row: `StatusMenu` as a prominent `Menu` button (label shows current
status or "Add to Library"), notifications `Toggle` (shows in library only),
share/link. Sections: **Next Episode** card (name, S/E, air date relative) when
known; **Progress** card (shows in library): "You're on S2 E5" / "Not started",
progress bar `ProgressView(value:)`, buttons "Mark Next Watched" and "Undo".
**Seasons** list (`NavigationLink` per regular season → `EpisodeListView`,
which fetches `season(showID:number:)` and shows `EpisodeRow`s with air dates,
a checkmark for watched (pointer ≥ episode), tap to set progress to that
episode, and "Mark season watched"). **Overview** with expandable text.
**Details** grouped rows (status, first/last aired, networks, runtime,
language, "View on TMDB" link). Custom items: no TMDB sections; **Edit** toolbar
button opens `CustomItemForm(item:)`; reminders row shows the schedule summary.
Toolbar: ellipsis menu (Refresh, Remove from Library).

**Search** — `SearchView` in the search tab: `.searchable(text:prompt: "Shows, Movies")`,
`.searchScopes` All / Shows / Movies, 300 ms debounce via task cancellation,
results `List` of `SearchResultRow` (50×75 poster, title, "2019 · Show", status
check if in library, trailing `plus.circle` quick-add `Menu`). Empty query:
"Trending this week" grid. No results: `ContentUnavailableView.search(text:)`
plus a "Add “<query>” as a custom title" button that opens `CustomItemForm`
prefilled. Errors show a retry.

**Custom item form** — `CustomItemForm(item: MediaItem? = nil, prefilledTitle: String? = nil, kind: MediaKind = .show)`
presented as a sheet with Cancel/Save. `Form` sections: Poster (`PhotosPicker`,
preview, remove), Details (Title, Type segmented, Overview multiline, Link,
Notes), Status picker, for shows: Progress (season/episode `Stepper`s), Total
episodes (optional), Reminders (`Toggle` "New episode reminders" → weekday
`Picker` + time `DatePicker(displayedComponents: .hourAndMinute)`). Save is
disabled with an empty title. Images are downscaled to 600px JPEG before
storing.

**Settings** — `SettingsView` sheet with Done. Sections: **TMDB** (status row,
`TokenEntryView` link: secure field, paste button, "Validate & Save", link to
https://www.themoviedb.org/settings/api, explanation of v4 token vs v3 key),
**Notifications** (authorization row + "Open Settings" via
`UIApplication.openNotificationSettingsURLString`, "Remind me at" `DatePicker`,
"Refresh episodes now" button with last-refresh footer, pending count),
**Content** (Region `Picker` over `Locale.Region.isoRegions` sorted by localized
name — used for In Theaters/Coming Soon), **Data** (item counts, "Delete All
Data" with confirmation dialog), **About** (version/build, TMDB attribution
"This product uses the TMDB API but is not endorsed or certified by TMDB.",
GitHub link).

**Onboarding** — `OnboardingView` `fullScreenCover`, 3 pages in a `TabView(.page)`:
Welcome (icon + three feature rows with SF Symbols), Connect TMDB (embedded
`TokenEntryView` content + "Skip for now"), Notifications ("Enable
Notifications" → request; "Not Now"). Continue/Get Started buttons
`.borderedProminent .controlSize(.large)`. Sets `settings.hasCompletedOnboarding`.

Haptics: `.sensoryFeedback(.success, trigger:)` when marking watched / adding.
Accessibility: poster buttons have labels; cards combine children; progress has
`accessibilityValue`. Dynamic Type: no fixed heights on text.

---

## 6. Conventions

* Swift 5 language mode, no force unwraps outside tests/previews, `guard` early
  exits, `// MARK: -` sections, one primary type per file.
* View models are `@MainActor @Observable final class`, owned with `@State`.
* Network calls only through `AppEnvironment.client`; UI must handle `nil`.
* Never block the main thread; all TMDB calls are `async`.
* Strings are plain literals (English); no localization tables yet.
* Tests: XCTest. App tests use `PreviewData`-style in-memory containers
  (`ModelConfiguration(isStoredInMemoryOnly: true)`).
* Do not add third-party dependencies.
