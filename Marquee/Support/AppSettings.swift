import Foundation
import Observation

// MARK: - AppSettings

/// User preferences, backed by `UserDefaults` and observable by SwiftUI.
@Observable
final class AppSettings {

    // MARK: Keys

    private enum Keys {
        static let hasCompletedOnboarding = "settings.hasCompletedOnboarding"
        static let reminderHour = "settings.reminderHour"
        static let reminderMinute = "settings.reminderMinute"
        static let region = "settings.region"
        static let lastLibraryRefresh = "settings.lastLibraryRefresh"
    }

    @ObservationIgnored
    private let defaults: UserDefaults

    // MARK: Stored preferences

    /// Whether the first-launch onboarding flow has been finished or skipped.
    var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: Keys.hasCompletedOnboarding) }
    }

    /// Hour (0...23) at which new-episode reminders fire. Default 9.
    var reminderHour: Int {
        didSet { defaults.set(reminderHour, forKey: Keys.reminderHour) }
    }

    /// Minute (0...59) at which new-episode reminders fire. Default 0.
    var reminderMinute: Int {
        didSet { defaults.set(reminderMinute, forKey: Keys.reminderMinute) }
    }

    /// ISO 3166-1 region used for In Theaters / Coming Soon.
    var region: String {
        didSet { defaults.set(region, forKey: Keys.region) }
    }

    /// When the library was last refreshed against TMDB.
    var lastLibraryRefresh: Date? {
        didSet {
            if let lastLibraryRefresh {
                defaults.set(lastLibraryRefresh, forKey: Keys.lastLibraryRefresh)
            } else {
                defaults.removeObject(forKey: Keys.lastLibraryRefresh)
            }
        }
    }

    // MARK: Init

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: Keys.hasCompletedOnboarding)
        self.reminderHour = (defaults.object(forKey: Keys.reminderHour) as? Int) ?? 9
        self.reminderMinute = (defaults.object(forKey: Keys.reminderMinute) as? Int) ?? 0
        self.region = defaults.string(forKey: Keys.region) ?? AppSettings.defaultRegion
        self.lastLibraryRefresh = defaults.object(forKey: Keys.lastLibraryRefresh) as? Date
    }

    // MARK: Derived

    /// The device's current region, or "US" when unavailable.
    static var defaultRegion: String {
        Locale.current.region?.identifier ?? "US"
    }

    /// `reminderHour`/`reminderMinute` as a `Date` today, for a `DatePicker`.
    var reminderTime: Date {
        get {
            let calendar = Calendar.current
            return calendar.date(bySettingHour: reminderHour, minute: reminderMinute, second: 0, of: .now) ?? .now
        }
        set {
            let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
            reminderHour = components.hour ?? 9
            reminderMinute = components.minute ?? 0
        }
    }
}
