import Foundation
import MarqueeKit

// MARK: - PlannedNotification

/// One local notification the app wants to have pending.
///
/// Produced by `NotificationPlanner` and turned into a `UNNotificationRequest`
/// by `NotificationManager`. Pure data, so planning can be unit tested without
/// touching `UserNotifications`.
struct PlannedNotification: Equatable, Identifiable {
    /// Notification request identifier (`EpisodeReminder.identifier` / `customIdentifier`).
    let id: String
    let title: String
    let body: String
    /// Calendar trigger components: year/month/day/hour/minute for one-off episode
    /// reminders, weekday/hour/minute for repeating custom-show reminders.
    let dateComponents: DateComponents
    let repeats: Bool
    /// The library item this reminder belongs to.
    let itemID: UUID
}

// MARK: - NotificationPlanner

/// Computes the set of reminders that should be pending for a list of library
/// items. Pure and deterministic: the result is sorted by identifier.
///
/// Rules:
/// * A TMDB show (`tmdbID != nil`) with `notificationsEnabled`, a known
///   `nextEpisodeAirDate` and a next episode season/number yields one
///   non-repeating reminder at the user's reminder time on the air date. Air
///   dates whose reminder moment is already in the past are skipped.
/// * A custom show with `notificationsEnabled` and a `releaseSchedule` yields
///   one repeating weekly reminder.
/// * Movies and items without notifications enabled are ignored.
enum NotificationPlanner {

    /// Body text used for repeating custom-show reminders.
    static let customReminderBody = "A new episode should be out now."

    /// Plans reminders for `items`.
    /// - Parameters:
    ///   - items: Library items to consider (any kind; non-qualifying items are ignored).
    ///   - reminderHour: Hour of day (0...23) for episode reminders.
    ///   - reminderMinute: Minute (0...59) for episode reminders.
    ///   - now: Reference instant; reminders at or before it are dropped.
    ///   - calendar: Calendar used to interpret air dates.
    static func plan(
        items: [MediaItem],
        reminderHour: Int,
        reminderMinute: Int,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [PlannedNotification] {
        var planned: [PlannedNotification] = []
        planned.reserveCapacity(items.count)

        for item in items {
            guard item.notificationsEnabled, item.kind == .show else { continue }

            if item.tmdbID != nil {
                if let reminder = episodeReminder(
                    for: item,
                    hour: reminderHour,
                    minute: reminderMinute,
                    now: now,
                    calendar: calendar
                ) {
                    planned.append(reminder)
                }
            } else if item.isCustom {
                if let reminder = customReminder(for: item) {
                    planned.append(reminder)
                }
            }
        }

        return planned.sorted { $0.id < $1.id }
    }

    // MARK: Private

    /// One-off reminder for a TMDB show's next episode, or `nil` when the
    /// episode is unknown or its reminder moment has passed.
    private static func episodeReminder(
        for item: MediaItem,
        hour: Int,
        minute: Int,
        now: Date,
        calendar: Calendar
    ) -> PlannedNotification? {
        guard let airDate = item.nextEpisodeAirDate,
              let season = item.nextEpisodeSeason,
              let number = item.nextEpisodeNumber else {
            return nil
        }
        let civilAirDate = CivilDate(airDate, calendar: calendar)
        guard let components = EpisodeReminder.fireComponents(
            airDate: civilAirDate,
            hour: hour,
            minute: minute,
            now: now,
            calendar: calendar
        ) else {
            return nil
        }
        let pointer = EpisodePointer(season: season, episode: number)
        let itemID = item.id
        return PlannedNotification(
            id: EpisodeReminder.identifier(itemID: itemID.uuidString, pointer: pointer),
            title: EpisodeReminder.title(showTitle: item.title),
            body: EpisodeReminder.body(pointer: pointer, episodeName: item.nextEpisodeName),
            dateComponents: components,
            repeats: false,
            itemID: itemID
        )
    }

    /// Weekly repeating reminder for a custom show, or `nil` without a schedule.
    private static func customReminder(for item: MediaItem) -> PlannedNotification? {
        guard let schedule = item.releaseSchedule else { return nil }
        let itemID = item.id
        return PlannedNotification(
            id: EpisodeReminder.customIdentifier(itemID: itemID.uuidString),
            title: EpisodeReminder.title(showTitle: item.title),
            body: customReminderBody,
            dateComponents: schedule.dateComponents,
            repeats: true,
            itemID: itemID
        )
    }
}
