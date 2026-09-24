import Foundation

// MARK: - ReleaseSchedule

/// Weekly release cadence for custom shows ("Tuesdays at 8:00 PM").
public struct ReleaseSchedule: Hashable, Codable, Sendable {
    /// 1 = Sunday ... 7 = Saturday (the `Calendar` convention).
    public var weekday: Int
    /// 0...23
    public var hour: Int
    /// 0...59
    public var minute: Int

    public init(weekday: Int, hour: Int, minute: Int) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }

    // MARK: Derived values

    /// Weekday, hour and minute only, suitable for a repeating calendar notification trigger.
    public var dateComponents: DateComponents {
        var components = DateComponents()
        components.weekday = weekday
        components.hour = hour
        components.minute = minute
        return components
    }

    /// The first instant strictly after `date` that matches this schedule in `calendar`.
    public func nextOccurrence(after date: Date, calendar: Calendar = .current) -> Date? {
        let startOfDay = calendar.startOfDay(for: date)
        // Fourteen days comfortably covers one full week plus DST/boundary quirks.
        for offset in 0...14 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: startOfDay) else { continue }
            let dayComponents = calendar.dateComponents([.year, .month, .day, .weekday], from: day)
            guard dayComponents.weekday == weekday else { continue }
            var fire = DateComponents()
            fire.year = dayComponents.year
            fire.month = dayComponents.month
            fire.day = dayComponents.day
            fire.hour = hour
            fire.minute = minute
            fire.second = 0
            guard let candidate = calendar.date(from: fire), candidate > date else { continue }
            return candidate
        }
        return nil
    }

    /// Human-readable summary such as "Tuesdays at 8:00 PM" (locale-aware time text).
    public func summary(calendar: Calendar = .current) -> String {
        let symbols = calendar.weekdaySymbols
        let index = weekday - 1
        let dayName: String = symbols.indices.contains(index) ? symbols[index] : "Day"
        return "\(dayName)s at \(timeText(calendar: calendar))"
    }

    // MARK: Helpers

    private func timeText(calendar: Calendar) -> String {
        var components = DateComponents()
        components.year = 2001
        components.month = 1
        components.day = 1
        components.hour = hour
        components.minute = minute
        components.second = 0
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = calendar.locale ?? Locale.current
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        if let date = calendar.date(from: components) {
            return formatter.string(from: date)
        }
        return fallbackTimeText
    }

    private var fallbackTimeText: String {
        let paddedMinute = minute < 10 ? "0\(minute)" : "\(minute)"
        return "\(hour):\(paddedMinute)"
    }
}
