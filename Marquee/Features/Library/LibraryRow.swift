import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - LibraryRow

/// One library item: 56×84 poster, title, progress subtitle, next-episode line
/// and a trailing "mark watched" button. The row itself navigates to the
/// item's detail; swipe actions and the context menu cover status moves,
/// reminders, editing (custom items) and deletion.
///
/// API:
///   LibraryRow(item: MediaItem, onMarked: (() -> Void)? = nil)
///
/// `onMarked` fires after an episode or movie is marked watched so the
/// enclosing screen can drive haptics.
struct LibraryRow: View {

    let item: MediaItem
    let onMarked: (() -> Void)?

    @Environment(\.modelContext) private var modelContext
    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isEditingCustomItem = false

    init(item: MediaItem, onMarked: (() -> Void)? = nil) {
        self.item = item
        self.onMarked = onMarked
    }

    private var store: LibraryStore {
        LibraryStore(context: modelContext)
    }

    // MARK: Body

    var body: some View {
        NavigationLink(value: LibraryRoute.item(item.id)) {
            rowContent
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            leadingSwipeActions
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            trailingSwipeActions
        }
        .contextMenu {
            contextMenuItems
        }
        .sheet(isPresented: $isEditingCustomItem) {
            CustomItemForm(item: item)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var rowContent: some View {
        if dynamicTypeSize.isAccessibilitySize {
            // Poster and button on top, text below at full width, so the
            // title is not squeezed into a sliver at accessibility sizes.
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 12) {
                    PosterView(item: item, width: 56, cornerRadius: 8)
                    Spacer(minLength: 8)
                    trailingButton
                }
                textBlock
            }
            .padding(.vertical, 4)
        } else {
            HStack(alignment: .center, spacing: 12) {
                PosterView(item: item, width: 56, cornerRadius: 8)
                textBlock
                Spacer(minLength: 8)
                trailingButton
            }
            .padding(.vertical, 4)
        }
    }

    /// Line limit for the secondary lines; unlimited at accessibility sizes.
    private var secondaryLineLimit: Int? {
        dynamicTypeSize.isAccessibilitySize ? nil : 1
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(item.title)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(secondaryLineLimit)
            nextEpisodeLine
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var nextEpisodeLine: some View {
        if item.isShow, item.status != .watched, let label = item.nextEpisodeLabel {
            HStack(spacing: 4) {
                if item.notificationsEnabled {
                    Image(systemName: "bell.fill")
                        .imageScale(.small)
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Reminders on")
                }
                Text(label)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(secondaryLineLimit)
        }
    }

    @ViewBuilder
    private var trailingButton: some View {
        if let action = primaryAction {
            Button {
                performPrimaryAction()
            } label: {
                Image(systemName: "checkmark.circle")
                    .imageScale(.large)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(action.title)
        }
    }

    // MARK: Subtitle

    private var subtitle: String {
        item.isMovie ? movieSubtitle : showSubtitle
    }

    /// "2024 · 2h 47m"
    private var movieSubtitle: String {
        var parts: [String] = []
        if let year = item.year {
            parts.append(String(year))
        }
        if let runtime = item.runtimeMinutes, runtime > 0 {
            parts.append(Formatters.runtime(minutes: runtime))
        }
        return parts.isEmpty ? "Movie" : parts.joined(separator: " · ")
    }

    /// "S2 E5 · 12 of 24", "Not started · 28 episodes", "Caught up · 19 of 19"
    private var showSubtitle: String {
        var parts: [String] = []
        if let progressText = ProgressBadge.text(for: item) {
            parts.append(progressText)
        }
        let watched = item.watchedEpisodeCount
        if let total = item.episodeTotal, total > 0 {
            if watched > 0 {
                parts.append("\(watched) of \(total)")
            } else {
                parts.append(total == 1 ? "1 episode" : "\(total) episodes")
            }
        } else if watched > 0 {
            parts.append(watched == 1 ? "1 episode watched" : "\(watched) episodes watched")
        }
        if parts.isEmpty, let year = item.year {
            parts.append(String(year))
        }
        return parts.isEmpty ? "Show" : parts.joined(separator: " · ")
    }

    // MARK: Primary action

    /// What the trailing button / leading swipe does for this item.
    private enum PrimaryAction {
        case markNextEpisode(EpisodePointer)
        case markMovieWatched

        /// Full title for menus and accessibility.
        var title: String {
            switch self {
            case .markNextEpisode(let pointer):
                return "Mark \(pointer.label) Watched"
            case .markMovieWatched:
                return "Mark Watched"
            }
        }

        /// Short title for the swipe button.
        var swipeTitle: String {
            switch self {
            case .markNextEpisode(let pointer):
                return pointer.label
            case .markMovieWatched:
                return "Watched"
            }
        }
    }

    private var primaryAction: PrimaryAction? {
        if item.isShow {
            guard item.status != .watched, let next = item.nextUp else { return nil }
            // Mirror the detail screen: no marking an episode TMDB says has not aired yet.
            if let pointer = item.nextEpisodePointer,
               let airDate = item.nextEpisodeAirDate,
               pointer == next,
               airDate > Date.now {
                return nil
            }
            return .markNextEpisode(next)
        }
        return item.status == .watched ? nil : .markMovieWatched
    }

    private func performPrimaryAction() {
        guard let action = primaryAction else { return }
        switch action {
        case .markNextEpisode:
            withAnimation {
                store.markNextEpisodeWatched(item)
            }
            scheduleNotificationSync()
        case .markMovieWatched:
            withAnimation {
                store.markMovieWatched(item)
            }
        }
        onMarked?()
    }

    // MARK: Swipe actions

    @ViewBuilder
    private var leadingSwipeActions: some View {
        if let action = primaryAction {
            Button {
                performPrimaryAction()
            } label: {
                Label(action.swipeTitle, systemImage: "checkmark")
            }
            .tint(.green)
        }
    }

    @ViewBuilder
    private var trailingSwipeActions: some View {
        Button(role: .destructive) {
            delete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
        ForEach(otherStatuses) { status in
            Button {
                setStatus(status)
            } label: {
                Label(status.displayName, systemImage: status.symbolName)
            }
            .tint(LibraryRow.tint(for: status))
        }
    }

    // MARK: Context menu

    @ViewBuilder
    private var contextMenuItems: some View {
        Section {
            if let action = primaryAction {
                Button {
                    performPrimaryAction()
                } label: {
                    Label(action.title, systemImage: "checkmark.circle")
                }
            }
            ForEach(contextMenuStatuses) { status in
                Button {
                    setStatus(status)
                } label: {
                    Label(LibraryRow.moveTitle(for: status), systemImage: status.symbolName)
                }
            }
        }
        if item.isShow || item.isCustom {
            Section {
                if item.isShow, !item.isCustom || item.releaseSchedule != nil {
                    Toggle("New Episode Reminders", systemImage: "bell", isOn: notificationsBinding)
                }
                if item.isCustom {
                    Button("Edit", systemImage: "pencil") {
                        isEditingCustomItem = true
                    }
                }
            }
        }
        Section {
            Button("Delete", systemImage: "trash", role: .destructive) {
                delete()
            }
        }
    }

    // MARK: Status

    private var otherStatuses: [WatchStatus] {
        WatchStatus.allCases.filter { $0 != item.status }
    }

    /// Statuses offered in the context menu. For movies the primary action
    /// already is "Mark Watched", so `.watched` is left out to avoid a duplicate row.
    private var contextMenuStatuses: [WatchStatus] {
        otherStatuses.filter { !(item.isMovie && $0 == .watched) }
    }

    private func setStatus(_ status: WatchStatus) {
        withAnimation {
            store.setStatus(item, to: status)
        }
        if status == .watched {
            onMarked?()
        }
    }

    private static func moveTitle(for status: WatchStatus) -> String {
        switch status {
        case .watching: return "Move to Watching"
        case .watchlist: return "Move to Watchlist"
        case .watched: return "Mark Watched"
        }
    }

    private static func tint(for status: WatchStatus) -> Color {
        switch status {
        case .watching: return .blue
        case .watchlist: return .orange
        case .watched: return .green
        }
    }

    // MARK: Notifications

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { item.notificationsEnabled },
            set: { enabled in setNotifications(enabled) }
        )
    }

    private func setNotifications(_ enabled: Bool) {
        store.setNotifications(item, enabled: enabled)
        Task {
            if enabled, !appEnvironment.notifications.isAuthorized {
                _ = await appEnvironment.notifications.requestAuthorization()
            }
            await syncNotifications()
        }
    }

    private func scheduleNotificationSync() {
        Task {
            await syncNotifications()
        }
    }

    private func syncNotifications() async {
        await appEnvironment.notifications.sync(
            items: store.showsWithNotificationsEnabled(),
            settings: appEnvironment.settings
        )
    }

    // MARK: Delete

    private func delete() {
        appEnvironment.notifications.cancel(for: item)
        withAnimation {
            store.delete(item)
        }
    }
}

// MARK: - Preview

#Preview("Library rows") {
    NavigationStack {
        List {
            Section {
                LibraryRow(item: PreviewData.sampleShow)
                LibraryRow(item: PreviewData.sampleMovie)
                LibraryRow(item: PreviewData.sampleCustomShow)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library")
    }
    .modelContainer(PreviewData.container)
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
}
