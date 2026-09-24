import SwiftUI
import SwiftData
import PhotosUI
import UserNotifications
import UIKit
import MarqueeKit

// MARK: - CustomItemForm

/// Creates or edits a custom (non-TMDB) show or movie. Present it as a sheet;
/// it brings its own `NavigationStack` with Cancel and Save.
///
/// API:
///   CustomItemForm(item: MediaItem? = nil, prefilledTitle: String? = nil, kind: MediaKind = .show)
///
/// New items are persisted with `LibraryStore.addCustom`; edits update the
/// passed item in place. Photos are downscaled to a 600px JPEG before they are
/// stored. Saving re-syncs reminders (and asks for notification permission the
/// first time reminders are switched on).
struct CustomItemForm: View {

    private let item: MediaItem?
    private let initialDraft: CustomItemDraft

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openURL) private var openURL
    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var draft: CustomItemDraft
    @State private var pickerItem: PhotosPickerItem?
    @State private var isProcessingPhoto = false
    @State private var photoErrorMessage: String?
    @State private var isConfirmingDiscard = false
    @State private var saveCount = 0
    @FocusState private var focusedField: Field?

    private enum Field: Hashable {
        case title
        case overview
        case link
        case notes
        case totalEpisodes
    }

    // MARK: Init

    init(item: MediaItem? = nil, prefilledTitle: String? = nil, kind: MediaKind = .show) {
        self.item = item
        let draft = CustomItemDraft(item: item, prefilledTitle: prefilledTitle, kind: kind)
        self.initialDraft = draft
        self._draft = State(initialValue: draft)
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            Form {
                posterSection
                detailsSection
                statusSection
                if draft.kind == .show {
                    progressSection
                    remindersSection
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .confirmationDialog("Discard Changes?", isPresented: $isConfirmingDiscard, titleVisibility: .visible) {
                Button("Discard Changes", role: .destructive) {
                    dismiss()
                }
                Button("Keep Editing", role: .cancel) {}
            }
        }
        .interactiveDismissDisabled(hasChanges)
        .task(id: pickerItem) {
            await loadPickedPhoto()
        }
        .onChange(of: draft.episode) { _, episode in
            if episode > 0, draft.season == 0 {
                draft.season = 1
            }
        }
        .onChange(of: draft.season) { _, season in
            if season == 0, draft.episode > 0 {
                draft.episode = 0
            }
        }
        .onChange(of: draft.totalEpisodesText) { _, text in
            let digits = text.filter { $0.isASCII && $0.isNumber }
            if digits != text {
                draft.totalEpisodesText = digits
            }
        }
        .onChange(of: draft.remindersOn) { _, isOn in
            if isOn {
                requestAuthorizationIfNeeded()
            }
        }
        .onAppear {
            if !isEditing, trimmedTitle.isEmpty {
                focusedField = .title
            }
        }
        .sensoryFeedback(.success, trigger: saveCount)
    }

    // MARK: Sections

    private var posterSection: some View {
        Section("Poster") {
            HStack(alignment: .center, spacing: 16) {
                posterPreview
                VStack(alignment: .leading, spacing: 12) {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Label(photoButtonTitle, systemImage: "photo")
                    }
                    if draft.posterData != nil {
                        Button("Remove Photo", systemImage: "trash", role: .destructive) {
                            removePhoto()
                        }
                    }
                    if let photoErrorMessage {
                        Text(photoErrorMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .buttonStyle(.borderless)
            }
            .padding(.vertical, 4)
        }
    }

    private var posterPreview: some View {
        PosterView(url: nil, imageData: draft.posterData, kind: draft.kind, width: 90)
            .overlay {
                if isProcessingPhoto {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.ultraThinMaterial)
                        ProgressView()
                    }
                }
            }
            .accessibilityLabel(draft.posterData == nil ? "No poster" : "Poster")
    }

    private var detailsSection: some View {
        Section {
            TextField("Title", text: $draft.title)
                .textInputAutocapitalization(.words)
                .focused($focusedField, equals: .title)
            Picker("Type", selection: $draft.kind) {
                ForEach(MediaKind.allCases) { kind in
                    Text(kind.displayName).tag(kind)
                }
            }
            .pickerStyle(.segmented)
            TextField("Overview", text: $draft.overview, axis: .vertical)
                .lineLimit(3...6)
                .focused($focusedField, equals: .overview)
            TextField("Link", text: $draft.link)
                .keyboardType(.URL)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .link)
            TextField("Notes", text: $draft.notes, axis: .vertical)
                .lineLimit(2...5)
                .focused($focusedField, equals: .notes)
        } header: {
            Text("Details")
        } footer: {
            if linkIsInvalid {
                Text("Enter a valid web address, like example.com.")
            }
        }
    }

    private var statusSection: some View {
        Section {
            Picker("Status", selection: $draft.status) {
                ForEach(WatchStatus.allCases) { status in
                    Label(status.displayName, systemImage: status.symbolName)
                        .tag(status)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var progressSection: some View {
        Section {
            Stepper("Season \(draft.season)", value: $draft.season, in: 0...100)
            Stepper("Episode \(draft.episode)", value: $draft.episode, in: 0...999)
            LabeledContent("Total Episodes") {
                TextField("Optional", text: $draft.totalEpisodesText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .focused($focusedField, equals: .totalEpisodes)
            }
        } header: {
            Text("Progress")
        } footer: {
            Text(progressFooter)
        }
    }

    private var remindersSection: some View {
        Section {
            Toggle("New Episode Reminders", isOn: $draft.remindersOn)
            if draft.remindersOn {
                Picker("Day", selection: $draft.weekday) {
                    ForEach(1...7, id: \.self) { day in
                        Text(CustomItemForm.weekdayName(day)).tag(day)
                    }
                }
                DatePicker("Time", selection: $draft.time, displayedComponents: .hourAndMinute)
                if notificationsDenied {
                    Button("Turn On Notifications in Settings", systemImage: "bell.slash") {
                        openNotificationSettings()
                    }
                }
            }
        } header: {
            Text("Reminders")
        } footer: {
            Text(remindersFooter)
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Cancel") {
                cancel()
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button("Save") {
                save()
            }
            .disabled(!canSave)
        }
        ToolbarItemGroup(placement: .keyboard) {
            Spacer()
            Button("Done") {
                focusedField = nil
            }
        }
    }

    // MARK: Derived state

    private var isEditing: Bool {
        item != nil
    }

    private var navigationTitle: String {
        if isEditing {
            return "Edit Title"
        }
        return draft.kind == .show ? "New Show" : "New Movie"
    }

    private var trimmedTitle: String {
        draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var hasChanges: Bool {
        draft != initialDraft
    }

    private var canSave: Bool {
        !trimmedTitle.isEmpty && !linkIsInvalid && !isProcessingPhoto
    }

    private var photoButtonTitle: String {
        draft.posterData == nil ? "Choose Photo" : "Change Photo"
    }

    private var linkURL: URL? {
        CustomItemForm.url(from: draft.link)
    }

    private var linkIsInvalid: Bool {
        let trimmed = draft.link.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && linkURL == nil
    }

    /// The last-watched pointer the form describes; `.notStarted` for season 0.
    private var progressPointer: EpisodePointer {
        guard draft.kind == .show, draft.season > 0 else { return .notStarted }
        return EpisodePointer(season: draft.season, episode: draft.episode)
    }

    private var totalEpisodes: Int? {
        guard draft.kind == .show, let value = Int(draft.totalEpisodesText), value > 0 else { return nil }
        return value
    }

    private var remindersEnabled: Bool {
        draft.kind == .show && draft.remindersOn
    }

    /// Weekly schedule from the Day / Time controls, only while reminders are on.
    private var schedule: ReleaseSchedule? {
        guard remindersEnabled else { return nil }
        let components = Calendar.current.dateComponents([.hour, .minute], from: draft.time)
        return ReleaseSchedule(
            weekday: min(max(draft.weekday, 1), 7),
            hour: components.hour ?? 20,
            minute: components.minute ?? 0
        )
    }

    private var notificationsDenied: Bool {
        appEnvironment.notifications.authorizationStatus == .denied
    }

    private var progressFooter: String {
        let pointer = progressPointer
        guard pointer.isStarted else {
            return "Leave both at 0 if you haven’t started yet."
        }
        var text = "Last watched \(pointer.label)."
        if let total = totalEpisodes {
            let remaining = max(total - pointer.episode, 0)
            switch remaining {
            case 0:
                text += " You’re caught up."
            case 1:
                text += " 1 episode left."
            default:
                text += " \(remaining) episodes left."
            }
        }
        return text
    }

    private var remindersFooter: String {
        var text = "Custom shows don’t have episode data, so Marquee reminds you once a week at the day and time you choose."
        if draft.remindersOn, notificationsDenied {
            text += " Notifications are currently turned off for Marquee."
        }
        return text
    }

    // MARK: Actions

    private func cancel() {
        if hasChanges {
            isConfirmingDiscard = true
        } else {
            dismiss()
        }
    }

    private func save() {
        guard canSave else { return }
        let store = LibraryStore(context: modelContext)
        if let item {
            update(item, store: store)
        } else {
            create(store: store)
        }
        saveCount += 1

        let wantsReminders = remindersEnabled
        let environment = appEnvironment
        Task { @MainActor in
            if wantsReminders, environment.notifications.authorizationStatus == .notDetermined {
                _ = await environment.notifications.requestAuthorization()
            }
            await environment.notifications.sync(
                items: store.showsWithNotificationsEnabled(),
                settings: environment.settings
            )
        }
        dismiss()
    }

    private func create(store: LibraryStore) {
        let created = store.addCustom(
            title: trimmedTitle,
            kind: draft.kind,
            status: draft.status,
            overview: draft.overview.trimmingCharacters(in: .whitespacesAndNewlines),
            posterData: draft.posterData,
            linkURL: linkURL,
            notes: draft.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            totalEpisodes: totalEpisodes,
            schedule: schedule,
            notificationsEnabled: remindersEnabled
        )
        let pointer = progressPointer
        if pointer.isStarted {
            store.setProgress(created, to: pointer)
        }
    }

    private func update(_ item: MediaItem, store: LibraryStore) {
        item.title = trimmedTitle
        item.kind = draft.kind
        item.overview = draft.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        item.customPosterData = draft.posterData
        item.linkURL = linkURL
        item.notes = draft.notes.trimmingCharacters(in: .whitespacesAndNewlines)

        if draft.kind == .show {
            item.totalEpisodes = totalEpisodes
            item.releaseSchedule = schedule
            item.notificationsEnabled = remindersEnabled
        } else {
            item.totalEpisodes = nil
            item.releaseSchedule = nil
            item.notificationsEnabled = false
            item.progress = .notStarted
        }
        item.updatedAt = .now

        if item.status != draft.status {
            store.setStatus(item, to: draft.status)
        }

        let pointer = progressPointer
        if draft.kind == .show, item.progress != pointer {
            if pointer.isStarted {
                store.setProgress(item, to: pointer)
            } else {
                item.progress = .notStarted
            }
        }
        store.save()
    }

    // MARK: Photos

    private func loadPickedPhoto() async {
        guard let pickerItem else { return }
        isProcessingPhoto = true
        photoErrorMessage = nil
        defer { isProcessingPhoto = false }

        do {
            guard let data = try await pickerItem.loadTransferable(type: Data.self) else {
                photoErrorMessage = "That photo couldn’t be loaded."
                return
            }
            let downscaled = await Task.detached(priority: .userInitiated) {
                ImageDownscaler.jpegData(from: data, maxDimension: 600, quality: 0.8)
            }.value
            guard !Task.isCancelled else { return }
            if let downscaled {
                draft.posterData = downscaled
            } else {
                photoErrorMessage = "That photo couldn’t be used as a poster."
            }
        } catch {
            guard !Task.isCancelled else { return }
            photoErrorMessage = "That photo couldn’t be loaded."
        }
        // Clear the selection so picking the same photo again re-triggers the task.
        self.pickerItem = nil
    }

    private func removePhoto() {
        draft.posterData = nil
        photoErrorMessage = nil
        pickerItem = nil
    }

    // MARK: Notifications

    private func requestAuthorizationIfNeeded() {
        guard appEnvironment.notifications.authorizationStatus == .notDetermined else { return }
        let environment = appEnvironment
        Task { @MainActor in
            _ = await environment.notifications.requestAuthorization()
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
    }

    // MARK: Helpers

    /// Localized weekday name for a `Calendar` weekday (1 = Sunday).
    static func weekdayName(_ weekday: Int) -> String {
        let symbols = Calendar.current.weekdaySymbols
        let index = weekday - 1
        guard symbols.indices.contains(index) else { return "Day \(weekday)" }
        return symbols[index]
    }

    /// A web URL from free text; "example.com" becomes "https://example.com".
    /// Returns `nil` for empty or unusable input.
    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(" ") else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let url = URL(string: candidate),
              let scheme = url.scheme, !scheme.isEmpty,
              let host = url.host(), !host.isEmpty else {
            return nil
        }
        return url
    }
}

// MARK: - CustomItemDraft

/// Everything the form edits, as one value so unsaved changes are easy to detect.
private struct CustomItemDraft: Equatable {
    var title: String
    var kind: MediaKind
    var overview: String
    var link: String
    var notes: String
    var status: WatchStatus
    var season: Int
    var episode: Int
    var totalEpisodesText: String
    var remindersOn: Bool
    /// 1 = Sunday ... 7 = Saturday.
    var weekday: Int
    /// Only the hour and minute are used.
    var time: Date
    var posterData: Data?

    init(item: MediaItem?, prefilledTitle: String?, kind: MediaKind) {
        let calendar = Calendar.current
        let defaultWeekday = calendar.component(.weekday, from: .now)
        let defaultTime = calendar.date(bySettingHour: 20, minute: 0, second: 0, of: .now) ?? .now

        guard let item else {
            title = prefilledTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            self.kind = kind
            overview = ""
            link = ""
            notes = ""
            status = .watching
            season = 0
            episode = 0
            totalEpisodesText = ""
            remindersOn = false
            weekday = defaultWeekday
            time = defaultTime
            posterData = nil
            return
        }

        title = item.title
        self.kind = item.kind
        overview = item.overview
        link = item.linkURL?.absoluteString ?? ""
        notes = item.notes
        status = item.status
        season = item.progressSeason
        episode = item.progressEpisode
        totalEpisodesText = item.totalEpisodes.map { String($0) } ?? ""
        remindersOn = item.notificationsEnabled
        if let schedule = item.releaseSchedule {
            weekday = schedule.weekday
            time = calendar.date(bySettingHour: schedule.hour, minute: schedule.minute, second: 0, of: .now) ?? defaultTime
        } else {
            weekday = defaultWeekday
            time = defaultTime
        }
        posterData = item.customPosterData
    }
}

// MARK: - Preview

#Preview("New show") {
    CustomItemForm(prefilledTitle: "Studio Rewatch Club", kind: .show)
        .modelContainer(PreviewData.container)
        .environment(AppEnvironment.shared)
}

#Preview("New movie") {
    CustomItemForm(kind: .movie)
        .modelContainer(PreviewData.container)
        .environment(AppEnvironment.shared)
}

#Preview("Edit") {
    CustomItemForm(item: PreviewData.sampleCustomShow)
        .modelContainer(PreviewData.container)
        .environment(AppEnvironment.shared)
}
