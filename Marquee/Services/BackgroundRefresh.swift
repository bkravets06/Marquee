import Foundation
import BackgroundTasks
import SwiftData
import os

// MARK: - BackgroundRefresh

/// Periodic background refresh of the library via `BGTaskScheduler`.
///
/// `register(container:environment:)` must be called from
/// `application(_:didFinishLaunchingWithOptions:)`; `schedule()` is called
/// whenever the app goes to the background and again from the task handler so
/// the refresh keeps recurring. The task identifier must also be listed under
/// `BGTaskSchedulerPermittedIdentifiers` in Info.plist.
enum BackgroundRefresh {

    /// Identifier registered in Info.plist.
    static let taskIdentifier = "com.bjkravets.marquee.refresh"

    /// Earliest delay between two background refreshes.
    static let minimumInterval: TimeInterval = 6 * 3_600

    private static let logger = Logger(subsystem: "com.bjkravets.marquee", category: "BackgroundRefresh")

    // MARK: Registration

    /// Registers the launch handler. Call exactly once, during app launch.
    static func register(container: ModelContainer, environment: AppEnvironment) {
        let registered = BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }
            handle(refreshTask, container: container, environment: environment)
        }
        if !registered {
            logger.error("Could not register background task \(taskIdentifier, privacy: .public)")
        }
    }

    // MARK: Scheduling

    /// Asks the system for another refresh no sooner than `minimumInterval`
    /// from now. Failures (for example on the simulator) are logged only.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: minimumInterval)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.notice("Could not schedule background refresh: \(error.localizedDescription, privacy: .public)")
        }
    }

    // MARK: Private

    private static func handle(_ refreshTask: BGAppRefreshTask, container: ModelContainer, environment: AppEnvironment) {
        // Queue the next run first so a crash or expiration does not break the cycle.
        schedule()

        let work = Task { @MainActor in
            let refresher = LibraryRefresher(environment: environment, context: container.mainContext)
            await refresher.refreshAll(force: false)
            guard !Task.isCancelled else { return }
            refreshTask.setTaskCompleted(success: true)
        }

        refreshTask.expirationHandler = {
            work.cancel()
            refreshTask.setTaskCompleted(success: false)
        }
    }
}
