#if DEBUG
import Foundation
import SwiftData
import MarqueeKit

// MARK: - DebugLaunchOptions

/// Launch arguments that make Debug builds easy to drive from scripts, such as
/// the CI smoke run that boots a simulator and captures screenshots.
///
/// Xcode registers `-key value` launch arguments in `UserDefaults`, so these
/// read straight from the standard defaults. Release builds do not compile
/// this file, so the arguments are ignored there.
///
///     -settings.hasCompletedOnboarding YES   skip onboarding (a real setting)
///     -marquee.initialTab library            discover | library | search
///     -marquee.seedLibrary YES               add a few titles when the library is empty
///     -marquee.openSeededItem YES            push the first seeded show's detail screen
enum DebugLaunchOptions {

    private static let defaults = UserDefaults.standard

    /// The tab to select on launch, if one was requested.
    static var initialTab: AppTab? {
        switch defaults.string(forKey: "marquee.initialTab")?.lowercased() {
        case "discover": return .discover
        case "library": return .library
        case "search": return .search
        default: return nil
        }
    }

    /// Whether an empty library should be filled with sample titles.
    static var seedsLibrary: Bool {
        defaults.bool(forKey: "marquee.seedLibrary")
    }

    /// Whether the first seeded show should be opened after seeding.
    static var opensSeededItem: Bool {
        defaults.bool(forKey: "marquee.openSeededItem")
    }
}

// MARK: - DebugSeeder

/// Fills an empty library with a few well-known titles so screenshots and
/// manual testing have something to show. Uses TMDB when a client is
/// available (real posters, seasons and next episodes); otherwise falls back
/// to the preview fixtures.
@MainActor
enum DebugSeeder {

    private struct Seed {
        let tmdbID: Int
        let kind: MediaKind
        let status: WatchStatus
        let progress: EpisodePointer?
        let notifications: Bool
    }

    private static let seeds: [Seed] = [
        // Severance
        Seed(tmdbID: 95396, kind: .show, status: .watching, progress: EpisodePointer(season: 2, episode: 4), notifications: true),
        // The Bear
        Seed(tmdbID: 136315, kind: .show, status: .watching, progress: EpisodePointer(season: 3, episode: 2), notifications: true),
        // Slow Horses
        Seed(tmdbID: 95480, kind: .show, status: .watching, progress: EpisodePointer(season: 1, episode: 5), notifications: false),
        // Breaking Bad
        Seed(tmdbID: 1396, kind: .show, status: .watchlist, progress: nil, notifications: false),
        // Dune: Part Two
        Seed(tmdbID: 693134, kind: .movie, status: .watchlist, progress: nil, notifications: false),
        // Past Lives
        Seed(tmdbID: 666277, kind: .movie, status: .watched, progress: nil, notifications: false),
    ]

    /// Seeds the library when `-marquee.seedLibrary YES` was passed and the
    /// library is empty, then opens the first watching show if requested.
    static func runIfRequested(context: ModelContext, environment: AppEnvironment, navigator: Navigator) async {
        guard DebugLaunchOptions.seedsLibrary else { return }
        let store = LibraryStore(context: context)
        var items = store.allItems()
        if items.isEmpty {
            items = await seed(into: store, client: environment.client)
        }
        guard DebugLaunchOptions.opensSeededItem else { return }
        let firstShow = items.first { $0.isShow && $0.status == .watching } ?? items.first
        guard let firstShow else { return }
        navigator.open(itemID: firstShow.id)
    }

    // MARK: Helpers

    private static func seed(into store: LibraryStore, client: TMDBClient?) async -> [MediaItem] {
        guard let client else {
            return PreviewData.sampleItems(context: store.context)
        }
        var created: [MediaItem] = []
        for seed in seeds {
            do {
                switch seed.kind {
                case .show:
                    let details = try await client.showDetails(id: seed.tmdbID)
                    let item = store.add(details.summary, status: seed.status)
                    store.apply(details, to: item)
                    if let progress = seed.progress {
                        store.setProgress(item, to: progress)
                    }
                    store.setNotifications(item, enabled: seed.notifications)
                    created.append(item)
                case .movie:
                    let details = try await client.movieDetails(id: seed.tmdbID)
                    let item = store.add(details.summary, status: seed.status)
                    store.apply(details, to: item)
                    created.append(item)
                }
            } catch {
                continue
            }
        }
        if created.isEmpty {
            return PreviewData.sampleItems(context: store.context)
        }
        return created
    }
}
#endif
