import Foundation

// MARK: - EpisodeReminder

/// Pure planning helpers for episode reminders. The app's `NotificationManager`
/// turns these into `UNNotificationRequest`s; the package only computes
/// identifiers, text and fire times.
public enum EpisodeReminder {

    // MARK: Identifiers

    public static let identifierPrefix = "marquee.episode."
    public static let customIdentifierPrefix = "marquee.custom."

    /// "marquee.episode.<id>.S2E5"
    public static func identifier(itemID: String, pointer: EpisodePointer) -> String {
        "\(identifierPrefix)\(itemID).S\(pointer.season)E\(pointer.episode)"
    }

    /// "marquee.custom.<id>"
    public static func customIdentifier(itemID: String) -> String {
        "\(customIdentifierPrefix)\(itemID)"
    }

    // MARK: Scheduling

    /// Year/month/day/hour/minute components for a reminder about an episode airing on `airDate`
    /// at the user's preferred `hour:minute`. Returns `nil` when that moment is not after `now`.
    public static func fireComponents(airDate: CivilDate, hour: Int, minute: Int, now: Date, calendar: Calendar = .current) -> DateComponents? {
        guard let fireDate = airDate.date(in: calendar, hour: hour, minute: minute), fireDate > now else {
            return nil
        }
        var components = DateComponents()
        components.year = airDate.year
        components.month = airDate.month
        components.day = airDate.day
        components.hour = hour
        components.minute = minute
        return components
    }

    // MARK: Text

    /// "New episode of <show>"
    public static func title(showTitle: String) -> String {
        "New episode of \(showTitle)"
    }

    /// "S2 E5 “Name” is out today." or, without a name, "S2 E5 is out today."
    public static func body(pointer: EpisodePointer, episodeName: String?) -> String {
        let trimmed = episodeName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            return "\(pointer.label) is out today."
        }
        return "\(pointer.label) \u{201C}\(trimmed)\u{201D} is out today."
    }
}
