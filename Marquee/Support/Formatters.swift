import Foundation

// MARK: - Formatters

/// Small, dependency-free formatting helpers shared across the UI.
enum Formatters {

    // MARK: Runtime and rating

    /// "1h 42m", "2h" or "48m".
    static func runtime(minutes: Int) -> String {
        let total = max(minutes, 0)
        let hours = total / 60
        let remainder = total % 60
        if hours > 0 && remainder > 0 {
            return "\(hours)h \(remainder)m"
        }
        if hours > 0 {
            return "\(hours)h"
        }
        return "\(remainder)m"
    }

    /// "8.1" style one-decimal rating.
    static func rating(_ value: Double) -> String {
        String(format: "%.1f", value)
    }

    // MARK: Dates

    /// Four-digit year for `date`, or `nil` when there is no date.
    static func year(from date: Date?, calendar: Calendar = .current) -> String? {
        guard let date else { return nil }
        return String(calendar.component(.year, from: date))
    }

    /// "Today", "Tomorrow", "Yesterday", a weekday within the next six days
    /// ("Thu"), otherwise "Oct 3" (with the year when it is not the current one).
    static func relativeAirDate(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let today = calendar.startOfDay(for: now)
        let day = calendar.startOfDay(for: date)
        let dayDelta = calendar.dateComponents([.day], from: today, to: day).day ?? 0

        switch dayDelta {
        case 0:
            return "Today"
        case 1:
            return "Tomorrow"
        case -1:
            return "Yesterday"
        case 2...6:
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone).weekday(.abbreviated)
            return date.formatted(style)
        default:
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            let style = Date.FormatStyle(calendar: calendar, timeZone: calendar.timeZone)
                .month(.abbreviated)
                .day()
            if sameYear {
                return date.formatted(style)
            }
            return date.formatted(style.year())
        }
    }

    /// "Oct 3, 2026".
    static func shortDate(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    /// "Oct 3, 2026 at 9:00 AM".
    static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    // MARK: Relative time

    /// Shared formatter producing "3h ago", "yesterday", "now".
    static let relativeDateTime: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.dateTimeStyle = .named
        return formatter
    }()

    /// "3h ago" relative to `now`.
    static func timeAgo(_ date: Date, now: Date = .now) -> String {
        relativeDateTime.localizedString(for: date, relativeTo: now)
    }

    /// "Updated 3h ago", or "Never updated" when there is no date.
    static func updatedAgo(_ date: Date?, now: Date = .now) -> String {
        guard let date else { return "Never updated" }
        return "Updated \(timeAgo(date, now: now))"
    }
}
