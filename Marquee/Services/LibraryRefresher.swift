import Foundation
import SwiftData
import MarqueeKit
import os

// MARK: - LibraryRefresher

/// Pulls fresh TMDB details for library shows and re-syncs episode reminders.
///
/// Create one per refresh (it is cheap) with the app's `AppEnvironment` and a
/// `ModelContext`, then call `refreshAll(force:)` from foreground activation or
/// the background task, or `refresh(item:)` from a detail screen.
@MainActor
final class LibraryRefresher {

    /// Shows refreshed less recently than this are considered stale.
    static let staleInterval: TimeInterval = 6 * 3_600

    private static let logger = Logger(subsystem: "com.bjkravets.marquee", category: "LibraryRefresher")

    private let environment: AppEnvironment
    private let context: ModelContext

    /// `true` while `refreshAll(force:)` is running on this instance.
    private(set) var isRefreshing = false

    init(environment: AppEnvironment, context: ModelContext) {
        self.environment = environment
        self.context = context
    }

    // MARK: Refresh all

    /// Refreshes every TMDB show that needs it, then re-syncs reminders and
    /// records `settings.lastLibraryRefresh`.
    ///
    /// - Parameter force: When `true`, refreshes every eligible show regardless
    ///   of how recently it was fetched.
    ///
    /// Per-item errors are swallowed so one bad show does not block the rest.
    /// An `unauthorized`, `missingCredentials` or `rateLimited` error stops the
    /// loop early since every following request would fail the same way.
    /// Without a TMDB client only the reminder sync runs (custom shows still
    /// need their repeating reminders kept current).
    func refreshAll(force: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let store = LibraryStore(context: context)

        guard let client = environment.client else {
            await syncNotifications(store: store)
            return
        }

        let interval: TimeInterval = force ? 0 : LibraryRefresher.staleInterval
        let items = store.showsNeedingRefresh(olderThan: interval)

        refreshLoop: for item in items {
            if Task.isCancelled { break }
            guard let tmdbID = item.tmdbID else { continue }
            do {
                let details = try await client.showDetails(id: tmdbID)
                store.apply(details, to: item)
            } catch let error as TMDBError {
                LibraryRefresher.logger.notice("Refresh of TMDB show \(tmdbID) failed: \(error.localizedDescription, privacy: .public)")
                if LibraryRefresher.shouldStop(after: error) {
                    break refreshLoop
                }
                continue
            } catch {
                LibraryRefresher.logger.notice("Refresh of TMDB show \(tmdbID) failed: \(error.localizedDescription, privacy: .public)")
                continue
            }
        }

        await syncNotifications(store: store)
        environment.settings.lastLibraryRefresh = .now
    }

    // MARK: Refresh one

    /// Refreshes a single library item from TMDB (shows and movies). Custom
    /// items are left untouched. Throws the underlying `TMDBError`.
    func refresh(item: MediaItem) async throws {
        guard let tmdbID = item.tmdbID else { return }
        guard let client = environment.client else {
            throw TMDBError.missingCredentials
        }
        let store = LibraryStore(context: context)

        switch item.kind {
        case .show:
            let details = try await client.showDetails(id: tmdbID)
            store.apply(details, to: item)
            await syncNotifications(store: store)
        case .movie:
            let details = try await client.movieDetails(id: tmdbID)
            store.apply(details, to: item)
        }
    }

    // MARK: Private

    private func syncNotifications(store: LibraryStore) async {
        await environment.notifications.sync(
            items: store.showsWithNotificationsEnabled(),
            settings: environment.settings
        )
    }

    /// Errors after which further requests are pointless right now.
    private static func shouldStop(after error: TMDBError) -> Bool {
        switch error {
        case .unauthorized, .missingCredentials, .rateLimited:
            return true
        case .notFound, .http, .decoding, .network:
            return false
        }
    }
}
