import Foundation

// MARK: - CivilDate

/// A calendar date without a time zone, matching TMDB's "YYYY-MM-DD" strings.
public struct CivilDate: Hashable, Comparable, Codable, Sendable, CustomStringConvertible {
    public var year: Int
    public var month: Int
    public var day: Int

    // MARK: Initializers

    public init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    /// Parses "YYYY-MM-DD". Returns `nil` for empty, malformed or out-of-range input.
    public init?(_ string: String) {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let parts = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        guard parts[0].count == 4, parts[1].count == 2, parts[2].count == 2 else { return nil }
        guard let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]) else { return nil }
        guard year >= 1, (1...12).contains(month) else { return nil }
        guard day >= 1, day <= CivilDate.daysInMonth(month, year: year) else { return nil }
        self.init(year: year, month: month, day: day)
    }

    /// The (Gregorian) civil date of `date` in `calendar`'s time zone.
    public init(_ date: Date, calendar: Calendar = .current) {
        let components = CivilDate.gregorian(matching: calendar).dateComponents([.year, .month, .day], from: date)
        self.init(year: components.year ?? 1970, month: components.month ?? 1, day: components.day ?? 1)
    }

    /// Today's civil date in `calendar`'s time zone.
    public static func today(calendar: Calendar = .current) -> CivilDate {
        CivilDate(Date(), calendar: calendar)
    }

    // MARK: Formatting

    /// "YYYY-MM-DD".
    public var string: String {
        CivilDate.pad(year, width: 4) + "-" + CivilDate.pad(month, width: 2) + "-" + CivilDate.pad(day, width: 2)
    }

    public var description: String { string }

    // MARK: Conversion

    /// The instant at `hour:minute` on this date in `calendar`'s time zone, or `nil` if it cannot be resolved.
    public func date(in calendar: Calendar = .current, hour: Int = 0, minute: Int = 0) -> Date? {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        components.second = 0
        return CivilDate.gregorian(matching: calendar).date(from: components)
    }

    /// Midnight at the start of this date in `calendar`.
    public func startOfDay(in calendar: Calendar = .current) -> Date? {
        date(in: calendar, hour: 0, minute: 0)
    }

    // MARK: Comparable

    public static func < (lhs: CivilDate, rhs: CivilDate) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        if lhs.month != rhs.month { return lhs.month < rhs.month }
        return lhs.day < rhs.day
    }

    // MARK: Codable

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let raw = try container.decode(String.self)
        guard let parsed = CivilDate(raw) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid civil date: \"\(raw)\"")
        }
        self = parsed
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(string)
    }

    // MARK: Helpers

    /// `calendar` itself when it is Gregorian, otherwise a Gregorian calendar in the same time zone and locale.
    /// Civil dates are always Gregorian ("YYYY-MM-DD", as TMDB sends them), so they must never be interpreted
    /// through a device calendar such as Buddhist or Japanese, whose year numbering differs.
    static func gregorian(matching calendar: Calendar) -> Calendar {
        switch calendar.identifier {
        case .gregorian, .iso8601:
            return calendar
        default:
            var gregorianCalendar = Calendar(identifier: .gregorian)
            gregorianCalendar.timeZone = calendar.timeZone
            gregorianCalendar.locale = calendar.locale
            return gregorianCalendar
        }
    }

    private static func pad(_ value: Int, width: Int) -> String {
        let digits = String(abs(value))
        let padding = max(0, width - digits.count)
        let prefix = value < 0 ? "-" : ""
        return prefix + String(repeating: "0", count: padding) + digits
    }

    private static func daysInMonth(_ month: Int, year: Int) -> Int {
        switch month {
        case 1, 3, 5, 7, 8, 10, 12: return 31
        case 4, 6, 9, 11: return 30
        case 2: return isLeapYear(year) ? 29 : 28
        default: return 0
        }
    }

    private static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}
