import Foundation
import Observation
import UserNotifications
import MarqueeKit
import os

// MARK: - NotificationManager

/// Owns the app's local notification state: authorization status and the set
/// of pending episode reminders.
///
/// `sync(items:settings:)` is the single entry point that reconciles what is
/// pending in `UNUserNotificationCenter` with what `NotificationPlanner` says
/// should be pending. It never requests authorization itself; call
/// `requestAuthorization()` from onboarding or Settings first.
@MainActor
@Observable
final class NotificationManager {

    private static let logger = Logger(subsystem: "com.bjkravets.marquee", category: "Notifications")

    /// Last known authorization status. Refresh with `refreshAuthorizationStatus()`.
    var authorizationStatus: UNAuthorizationStatus = .notDetermined

    /// `true` when the system will deliver notifications for this app.
    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    init() {}

    // MARK: Authorization

    /// Reads the current authorization status from the system.
    func refreshAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    /// Prompts for alert/sound/badge permission and returns whether it was granted.
    func requestAuthorization() async -> Bool {
        let granted: Bool
        do {
            granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            NotificationManager.logger.error("Authorization request failed: \(error.localizedDescription, privacy: .public)")
            granted = false
        }
        await refreshAuthorizationStatus()
        return granted
    }

    // MARK: Sync

    /// Reconciles pending reminders with the plan for `items`.
    ///
    /// Pending Marquee requests that are no longer planned are removed; planned
    /// requests that are missing (or whose trigger changed, e.g. after the
    /// reminder time was edited) are added. Does nothing when notifications are
    /// not authorized.
    func sync(items: [MediaItem], settings: AppSettings) async {
        let plan = NotificationPlanner.plan(
            items: items,
            reminderHour: settings.reminderHour,
            reminderMinute: settings.reminderMinute
        )

        await refreshAuthorizationStatus()
        guard isAuthorized else { return }

        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()

        var pendingByID: [String: UNNotificationRequest] = [:]
        for request in pending where NotificationManager.isMarqueeIdentifier(request.identifier) {
            pendingByID[request.identifier] = request
        }

        let desiredIDs = Set(plan.map { $0.id })
        let staleIDs = pendingByID.keys.filter { !desiredIDs.contains($0) }
        if !staleIDs.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: Array(staleIDs))
        }

        for planned in plan {
            if let existing = pendingByID[planned.id],
               NotificationManager.trigger(of: existing, matches: planned) {
                continue
            }
            let request = NotificationManager.makeRequest(for: planned)
            do {
                try await center.add(request)
            } catch {
                NotificationManager.logger.error("Could not schedule \(planned.id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Removes every pending reminder (episode and custom) for `item`.
    func cancel(for item: MediaItem) {
        let itemID = item.id.uuidString
        Task { @MainActor in
            await NotificationManager.removePendingRequests(forItemID: itemID)
        }
    }

    /// Removes every pending reminder for the item with `itemID`. Awaitable
    /// variant of `cancel(for:)` for callers that need completion.
    func cancelPending(forItemID itemID: UUID) async {
        await NotificationManager.removePendingRequests(forItemID: itemID.uuidString)
    }

    /// Number of pending requests that belong to Marquee.
    func pendingCount() async -> Int {
        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        return pending.filter { NotificationManager.isMarqueeIdentifier($0.identifier) }.count
    }

    // MARK: Helpers

    /// Whether `identifier` was created by Marquee.
    static func isMarqueeIdentifier(_ identifier: String) -> Bool {
        identifier.hasPrefix(EpisodeReminder.identifierPrefix)
            || identifier.hasPrefix(EpisodeReminder.customIdentifierPrefix)
    }

    /// Whether `identifier` belongs to the item with `itemID` (either pattern).
    static func identifier(_ identifier: String, belongsTo itemID: String) -> Bool {
        identifier.hasPrefix(EpisodeReminder.identifierPrefix + itemID + ".")
            || identifier == EpisodeReminder.customIdentifier(itemID: itemID)
    }

    private static func removePendingRequests(forItemID itemID: String) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let matching = pending
            .map { $0.identifier }
            .filter { NotificationManager.identifier($0, belongsTo: itemID) }
        guard !matching.isEmpty else { return }
        center.removePendingNotificationRequests(withIdentifiers: matching)
    }

    private static func makeRequest(for planned: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = planned.title
        content.body = planned.body
        content.sound = UNNotificationSound.default
        content.userInfo = ["itemID": planned.itemID.uuidString]
        content.threadIdentifier = planned.itemID.uuidString

        let trigger = UNCalendarNotificationTrigger(dateMatching: planned.dateComponents, repeats: planned.repeats)
        return UNNotificationRequest(identifier: planned.id, content: content, trigger: trigger)
    }

    /// `true` when the pending request already fires when `planned` wants it to.
    private static func trigger(of request: UNNotificationRequest, matches planned: PlannedNotification) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger else { return false }
        guard trigger.repeats == planned.repeats else { return false }
        let existing = trigger.dateComponents
        let wanted = planned.dateComponents
        return existing.year == wanted.year
            && existing.month == wanted.month
            && existing.day == wanted.day
            && existing.weekday == wanted.weekday
            && existing.hour == wanted.hour
            && existing.minute == wanted.minute
    }
}
