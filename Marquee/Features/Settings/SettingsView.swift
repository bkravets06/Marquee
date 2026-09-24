import SwiftUI
import SwiftData
import UIKit
import UserNotifications
import MarqueeKit

// MARK: - SettingsView

/// The Settings sheet: TMDB credential, notification preferences, catalog
/// region, library data and about information.
struct SettingsView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.scenePhase) private var scenePhase

    @State private var reminderTime: Date = .now
    @State private var pendingCount = 0
    @State private var isRefreshing = false
    @State private var counts = LibraryCounts()
    @State private var isConfirmingDelete = false
    @State private var feedbackCount = 0

    private static let githubURL = URL(string: "https://github.com/bkravets06/Marquee")

    init() {}

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                tmdbSection
                notificationsSection
                contentSection
                dataSection
                aboutSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Delete All Data?", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button(deleteButtonTitle, role: .destructive, action: deleteAllData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Every show and movie is removed from your library and all reminders are cancelled. Your TMDB key and settings are kept.")
            }
        }
        .onAppear {
            loadLocalState()
        }
        .task {
            await refreshNotificationState()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                await refreshNotificationState()
            }
        }
        .onChange(of: reminderTime) { _, newValue in
            reminderTimeChanged(to: newValue)
        }
        .sensoryFeedback(.success, trigger: feedbackCount)
    }

    // MARK: TMDB

    private var tmdbSection: some View {
        Section {
            LabeledContent("Status") {
                if appEnvironment.hasCredentials {
                    Label {
                        Text("Connected")
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                } else {
                    Text("Not Connected")
                        .foregroundStyle(.secondary)
                }
            }
            NavigationLink("API Key…") {
                TokenEntryView()
            }
        } header: {
            Text("TMDB")
        } footer: {
            Text("Discover and Search are powered by The Movie Database and need a free TMDB API key. Your library works without one.")
        }
    }

    // MARK: Notifications

    private var notificationsSection: some View {
        Section {
            LabeledContent("Permission", value: permissionText)
            permissionAction
            DatePicker("Remind Me At", selection: $reminderTime, displayedComponents: .hourAndMinute)
            refreshButton
        } header: {
            Text("Notifications")
        } footer: {
            Text(notificationsFooter)
        }
    }

    @ViewBuilder
    private var permissionAction: some View {
        switch appEnvironment.notifications.authorizationStatus {
        case .notDetermined:
            Button("Enable Notifications", action: enableNotifications)
        case .denied:
            Button("Open Settings", action: openNotificationSettings)
        default:
            EmptyView()
        }
    }

    private var refreshButton: some View {
        Button(action: refreshEpisodes) {
            HStack {
                Text("Refresh Episodes Now")
                Spacer()
                if isRefreshing {
                    ProgressView()
                }
            }
        }
        .disabled(isRefreshing)
    }

    private var permissionText: String {
        switch appEnvironment.notifications.authorizationStatus {
        case .authorized:
            return "Allowed"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not Requested"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Temporary"
        @unknown default:
            return "Unknown"
        }
    }

    private var notificationsFooter: String {
        let refreshed: String
        if let date = appEnvironment.settings.lastLibraryRefresh {
            refreshed = "Last refreshed \(Formatters.timeAgo(date))."
        } else {
            refreshed = "Episodes have not been refreshed yet."
        }
        let reminders = pendingCount == 1 ? "1 reminder scheduled." : "\(pendingCount) reminders scheduled."
        return "Marquee reminds you at this time on the day a new episode airs. \(refreshed) \(reminders)"
    }

    // MARK: Content

    private var contentSection: some View {
        Section {
            NavigationLink {
                RegionPicker(selection: regionBinding)
            } label: {
                LabeledContent("Region", value: regionName)
            }
        } header: {
            Text("Content")
        } footer: {
            Text("Used for In Theaters and Coming Soon in Discover.")
        }
    }

    private var regionBinding: Binding<String> {
        Binding(
            get: { appEnvironment.settings.region },
            set: { newValue in
                guard newValue != appEnvironment.settings.region else { return }
                appEnvironment.settings.region = newValue
                appEnvironment.rebuildClient()
            }
        )
    }

    private var regionName: String {
        let code = appEnvironment.settings.region
        return Locale.current.localizedString(forRegionCode: code) ?? code
    }

    // MARK: Data

    private var dataSection: some View {
        Section {
            LabeledContent("Watching", value: "\(counts.watching)")
            LabeledContent("Watchlist", value: "\(counts.watchlist)")
            LabeledContent("Watched", value: "\(counts.watched)")
            Button("Delete All Data", role: .destructive) {
                isConfirmingDelete = true
            }
            .disabled(counts.total == 0)
        } header: {
            Text("Data")
        } footer: {
            Text(dataFooter)
        }
    }

    private var dataFooter: String {
        guard counts.total > 0 else { return "Your library is empty." }
        let titles = counts.total == 1 ? "1 title" : "\(counts.total) titles"
        let shows = counts.shows == 1 ? "1 show" : "\(counts.shows) shows"
        let movies = counts.movies == 1 ? "1 movie" : "\(counts.movies) movies"
        return "\(titles) in your library: \(shows) and \(movies)."
    }

    private var deleteButtonTitle: String {
        counts.total == 1 ? "Delete 1 Title" : "Delete \(counts.total) Titles"
    }

    // MARK: About

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: versionText)
            if let url = SettingsView.githubURL {
                Link(destination: url) {
                    Label("Marquee on GitHub", systemImage: "link")
                }
            }
        } header: {
            Text("About")
        } footer: {
            Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
        }
    }

    private var versionText: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let version = (info["CFBundleShortVersionString"] as? String) ?? "1.0"
        let build = (info["CFBundleVersion"] as? String) ?? "1"
        return "\(version) (\(build))"
    }

    // MARK: Loading

    private func loadLocalState() {
        reminderTime = appEnvironment.settings.reminderTime
        loadCounts()
    }

    private func loadCounts() {
        let store = LibraryStore(context: modelContext)
        var next = LibraryCounts()
        for item in store.allItems() {
            switch item.status {
            case .watching:
                next.watching += 1
            case .watchlist:
                next.watchlist += 1
            case .watched:
                next.watched += 1
            }
            if item.isShow {
                next.shows += 1
            } else {
                next.movies += 1
            }
        }
        counts = next
    }

    private func refreshNotificationState() async {
        await appEnvironment.notifications.refreshAuthorizationStatus()
        pendingCount = await appEnvironment.notifications.pendingCount()
    }

    private func syncNotifications() async {
        let store = LibraryStore(context: modelContext)
        await appEnvironment.notifications.sync(
            items: store.showsWithNotificationsEnabled(),
            settings: appEnvironment.settings
        )
        pendingCount = await appEnvironment.notifications.pendingCount()
    }

    // MARK: Actions

    private func enableNotifications() {
        Task {
            let granted = await appEnvironment.notifications.requestAuthorization()
            if granted {
                await syncNotifications()
                feedbackCount += 1
            }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
    }

    /// Persists a new reminder time and reschedules pending reminders. Ignores
    /// the initial load, which sets the picker to the stored value.
    private func reminderTimeChanged(to newValue: Date) {
        let settings = appEnvironment.settings
        let components = Calendar.current.dateComponents([.hour, .minute], from: newValue)
        let unchanged = components.hour == settings.reminderHour && components.minute == settings.reminderMinute
        guard !unchanged else { return }
        settings.reminderTime = newValue
        Task {
            await syncNotifications()
        }
    }

    private func refreshEpisodes() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task {
            let refresher = LibraryRefresher(environment: appEnvironment, context: modelContext)
            await refresher.refreshAll(force: true)
            pendingCount = await appEnvironment.notifications.pendingCount()
            loadCounts()
            isRefreshing = false
            feedbackCount += 1
        }
    }

    private func deleteAllData() {
        Task {
            await cancelAllReminders()
            let store = LibraryStore(context: modelContext)
            store.deleteAll()
            loadCounts()
            pendingCount = await appEnvironment.notifications.pendingCount()
            feedbackCount += 1
        }
    }

    /// Removes every pending Marquee reminder, whether or not notifications are
    /// currently authorized.
    private func cancelAllReminders() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map { $0.identifier }
            .filter { NotificationManager.isMarqueeIdentifier($0) }
        if !identifiers.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: identifiers)
        }
        center.removeAllDeliveredNotifications()
    }
}

// MARK: - LibraryCounts

/// Item counts shown in the Data section.
private struct LibraryCounts: Equatable {
    var watching = 0
    var watchlist = 0
    var watched = 0
    var shows = 0
    var movies = 0

    var total: Int { watching + watchlist + watched }
}

// MARK: - Preview

#Preview {
    SettingsView()
        .environment(AppEnvironment.shared)
        .environment(Navigator.shared)
        .modelContainer(PreviewData.container)
}
