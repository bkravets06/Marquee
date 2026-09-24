import SwiftUI
import SwiftData
import os

// MARK: - MarqueeApp

@main
struct MarqueeApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ImageCache.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(AppEnvironment.shared)
                .environment(Navigator.shared)
        }
        .modelContainer(AppModelContainer.shared)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(to: newPhase)
        }
    }

    // MARK: Scene phase

    private func handleScenePhaseChange(to phase: ScenePhase) {
        switch phase {
        case .active:
            Task { @MainActor in
                let refresher = LibraryRefresher(
                    environment: AppEnvironment.shared,
                    context: AppModelContainer.shared.mainContext
                )
                await refresher.refreshAll(force: false)
                await AppEnvironment.shared.notifications.refreshAuthorizationStatus()
            }
        case .background:
            BackgroundRefresh.schedule()
        case .inactive:
            break
        @unknown default:
            break
        }
    }
}

// MARK: - AppModelContainer

/// The single SwiftData container used by the app, background tasks and the
/// notification delegate.
enum AppModelContainer {

    private static let logger = Logger(subsystem: "com.bjkravets.marquee", category: "Persistence")

    /// Opens the on-disk store; falls back to an in-memory store if that fails.
    static let shared: ModelContainer = {
        let schema = Schema([MediaItem.self])
        let persistent = ModelConfiguration("Marquee", schema: schema, isStoredInMemoryOnly: false)
        do {
            return try ModelContainer(for: schema, configurations: [persistent])
        } catch {
            logger.error("Could not open the persistent store, falling back to memory: \(error.localizedDescription, privacy: .public)")
        }

        let inMemory = ModelConfiguration("MarqueeInMemory", schema: schema, isStoredInMemoryOnly: true)
        do {
            return try ModelContainer(for: schema, configurations: [inMemory])
        } catch {
            fatalError("Marquee could not create a SwiftData container, even in memory: \(error)")
        }
    }()
}
