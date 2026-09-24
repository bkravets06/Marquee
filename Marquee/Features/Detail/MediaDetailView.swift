import SwiftUI
import SwiftData
import UIKit
import MarqueeKit

// MARK: - MediaDetailView

/// Detail screen for a show or movie: hero backdrop, poster and title block,
/// library status and reminder controls, then Next Episode, Progress,
/// Seasons, Overview and Details cards.
struct MediaDetailView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var model: DetailModel
    @State private var isEditing = false
    @State private var isConfirmingRemoval = false
    @State private var isOverviewExpanded = false
    @State private var isScrolledPastHero = false
    @State private var successCount = 0
    @State private var undoCount = 0

    init(reference: MediaReference) {
        _model = State(initialValue: DetailModel(reference: reference))
    }

    private var store: LibraryStore {
        LibraryStore(context: modelContext)
    }

    // MARK: Body

    var body: some View {
        content
            .background(Color(.systemGroupedBackground).ignoresSafeArea())
            .navigationTitle(model.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .sheet(isPresented: $isEditing) {
                editSheet
            }
            .confirmationDialog("Remove from Library?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
                Button("Remove", role: .destructive) {
                    removeFromLibrary()
                }
            } message: {
                Text("Your progress and reminders for this title will be deleted.")
            }
            .task(id: appEnvironment.hasCredentials) {
                await load()
            }
            .onAppear {
                // Coming back to this screen: the item may have been removed elsewhere.
                model.resolveItem(store: store)
            }
            .sensoryFeedback(.success, trigger: successCount)
            .sensoryFeedback(.impact(weight: .light), trigger: undoCount)
    }

    @ViewBuilder
    private var content: some View {
        if model.hasContent {
            scrollContent
        } else if model.showsPlaceholder {
            DetailPlaceholder(backdropHeight: 260)
        } else {
            unavailableView
        }
    }

    // MARK: Scroll content

    private var scrollContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                backdrop
                VStack(alignment: .leading, spacing: 20) {
                    headerRow
                    GenreChips(genres: model.genres, horizontalPadding: 16)
                    actionRow
                    errorBanner
                    Group {
                        nextEpisodeCard
                        progressCard
                        SeasonsView(model: model)
                        overviewCard
                        detailsCard
                        notesCard
                    }
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 32)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > backdropHeight - 120
        } action: { _, isPast in
            isScrolledPastHero = isPast
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                collapsedTitle
            }
        }
    }

    /// Inline title that fades in once the hero has scrolled away.
    private var collapsedTitle: some View {
        Text(model.title)
            .font(.headline)
            .lineLimit(1)
            .opacity(isScrolledPastHero ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: isScrolledPastHero)
            .accessibilityHidden(!isScrolledPastHero)
    }

    // MARK: Hero

    private var backdropHeight: CGFloat {
        if model.backdropURL == nil {
            return 180
        }
        return horizontalSizeClass == .regular ? 380 : 260
    }

    private var backdrop: some View {
        BackdropHeader(url: model.backdropURL, height: backdropHeight)
            .overlay(alignment: .top) {
                topScrim
            }
            .overlay(alignment: .bottom) {
                groupedFade
            }
    }

    /// Keeps the bar buttons legible over bright artwork.
    private var topScrim: some View {
        LinearGradient(
            colors: [Color.black.opacity(0.35), Color.black.opacity(0)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 120)
        .allowsHitTesting(false)
    }

    /// `BackdropHeader` fades into the plain system background; this page uses
    /// the grouped background, so fade the last stretch into that instead.
    private var groupedFade: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: Color(.systemGroupedBackground).opacity(0), location: 0),
                Gradient.Stop(color: Color(.systemGroupedBackground), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: backdropHeight * 0.5)
        .allowsHitTesting(false)
    }

    private var headerRow: some View {
        HStack(alignment: .bottom, spacing: 16) {
            PosterView(url: model.posterURL, imageData: model.posterData, kind: model.kind, width: 110)
                .padding(.top, -40)
                .accessibilityHidden(true)
            titleBlock
        }
        .padding(.horizontal, 16)
    }

    private var titleFont: Font {
        horizontalSizeClass == .compact ? Font.title2.bold() : Font.title.bold()
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(model.title)
                .font(titleFont)
                .fixedSize(horizontal: false, vertical: true)
            if let tagline = model.tagline {
                Text(tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            metadataLine
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var metadataLine: some View {
        HStack(spacing: 8) {
            KindBadge(kind: model.kind)
            if !model.metadataText.isEmpty {
                Text(model.metadataText)
            }
            RatingLabel(voteAverage: model.voteAverage)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    // MARK: Actions row

    private var actionRow: some View {
        VStack(spacing: 12) {
            StatusMenu(
                current: model.item?.status,
                style: .prominent,
                onSelect: { status in select(status) },
                onRemove: removeAction
            )
            .disabled(!model.canChangeStatus)
            if let item = model.item, item.isShow {
                notificationsControl(for: item)
            }
        }
        .padding(.horizontal, 16)
    }

    private var removeAction: (() -> Void)? {
        guard model.item != nil else { return nil }
        return { isConfirmingRemoval = true }
    }

    private func notificationsControl(for item: MediaItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("New Episode Alerts", systemImage: "bell.badge", isOn: notificationsBinding(for: item))
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if item.notificationsEnabled && appEnvironment.notifications.authorizationStatus == .denied {
                deniedNotice
            }
        }
    }

    private var deniedNotice: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Notifications are turned off for Marquee in Settings.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Open Settings") {
                openNotificationSettings()
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 4)
    }

    private func notificationsBinding(for item: MediaItem) -> Binding<Bool> {
        Binding(
            get: { item.notificationsEnabled },
            set: { enabled in setNotifications(enabled, for: item) }
        )
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let message = model.errorMessage {
            ErrorRetryView(message: message) {
                Task { await load() }
            }
            .padding(.horizontal, 16)
        }
    }

    // MARK: Cards

    @ViewBuilder
    private var nextEpisodeCard: some View {
        if let episode = model.nextEpisode {
            DetailCard("Next Episode") {
                NextEpisodeContent(episode: episode)
            }
        }
    }

    @ViewBuilder
    private var progressCard: some View {
        if let item = model.item, item.isShow {
            DetailCard("Progress") {
                ProgressCardContent(
                    item: item,
                    onMarkNext: { markNextWatched(item) },
                    onUndo: { undo(item) }
                )
            }
        }
    }

    @ViewBuilder
    private var overviewCard: some View {
        if !model.overview.isEmpty {
            DetailCard("Overview") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(model.overview)
                        .font(.body)
                        .lineLimit(isOverviewExpanded ? nil : 4)
                    if model.overview.count > 240 {
                        Button(isOverviewExpanded ? "Less" : "More") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isOverviewExpanded.toggle()
                            }
                        }
                        .font(.subheadline.weight(.semibold))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var detailsCard: some View {
        let entries = model.detailEntries
        if !entries.isEmpty {
            DetailCard("Details") {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        if index > 0 {
                            Divider()
                        }
                        DetailEntryRow(entry: entry)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var notesCard: some View {
        if let notes = model.item?.notes.trimmingCharacters(in: .whitespacesAndNewlines), !notes.isEmpty {
            DetailCard("Notes") {
                Text(notes)
                    .font(.body)
            }
        }
    }

    // MARK: Empty and error states

    private var unavailableView: some View {
        ContentUnavailableView {
            Label(unavailableTitle, systemImage: unavailableSymbol)
        } description: {
            Text(unavailableDescription)
        } actions: {
            if !model.isMissingLibraryItem {
                Button("Try Again") {
                    Task { await load() }
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var unavailableTitle: String {
        if model.isMissingLibraryItem { return "Not in Library" }
        if model.needsCredentials { return "Connect to TMDB" }
        return "Unable to Load"
    }

    private var unavailableSymbol: String {
        if model.isMissingLibraryItem { return "questionmark.circle" }
        if model.needsCredentials { return "key.fill" }
        return "exclamationmark.triangle"
    }

    private var unavailableDescription: String {
        if model.isMissingLibraryItem {
            return "This title was removed from your library."
        }
        return model.errorMessage ?? "Something went wrong while talking to TMDB."
    }

    // MARK: Toolbar and sheets

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .topBarTrailing) {
            if model.isCustom && model.item != nil {
                Button("Edit") {
                    isEditing = true
                }
            }
            if model.item != nil || model.tmdbID != nil {
                moreMenu
            }
        }
    }

    private var moreMenu: some View {
        Menu {
            if model.tmdbID != nil && appEnvironment.hasCredentials {
                Button("Refresh", systemImage: "arrow.clockwise") {
                    Task { await load() }
                }
            }
            if let url = model.tmdbURL {
                ShareLink(item: url)
                Link(destination: url) {
                    Label("View on TMDB", systemImage: "safari")
                }
            }
            if model.item != nil {
                Divider()
                Button("Remove from Library", systemImage: "trash", role: .destructive) {
                    isConfirmingRemoval = true
                }
            }
        } label: {
            Label("More", systemImage: "ellipsis.circle")
        }
    }

    @ViewBuilder
    private var editSheet: some View {
        if let item = model.item {
            CustomItemForm(item: item)
        }
    }

    // MARK: Loading

    private func load() async {
        await model.load(store: store, client: appEnvironment.client)
    }

    // MARK: Library actions

    private func select(_ status: WatchStatus) {
        if let item = model.item {
            store.setStatus(item, to: status)
        } else if let summary = model.summary {
            let added = store.add(summary, status: status)
            model.applyLoadedDetails(to: added, store: store)
            model.item = added
        } else {
            return
        }
        successCount += 1
    }

    private func markNextWatched(_ item: MediaItem) {
        store.markNextEpisodeWatched(item)
        successCount += 1
    }

    private func undo(_ item: MediaItem) {
        store.markPreviousEpisodeUnwatched(item)
        undoCount += 1
    }

    private func removeFromLibrary() {
        guard let item = model.item else { return }
        let popsAfterRemoval = model.isLibraryReference
        appEnvironment.notifications.cancel(for: item)
        model.item = nil
        store.delete(item)
        if popsAfterRemoval {
            dismiss()
        }
    }

    // MARK: Notifications

    private func setNotifications(_ enabled: Bool, for item: MediaItem) {
        guard item.notificationsEnabled != enabled else { return }
        store.setNotifications(item, enabled: enabled)
        let environment = appEnvironment
        let library = store
        Task { @MainActor in
            if enabled, environment.notifications.authorizationStatus == .notDetermined {
                _ = await environment.notifications.requestAuthorization()
            }
            await environment.notifications.sync(
                items: library.showsWithNotificationsEnabled(),
                settings: environment.settings
            )
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        openURL(url)
    }
}

// MARK: - DetailCard

/// Rounded card with a headline title, matching inset-grouped list cells.
struct DetailCard<Content: View>: View {

    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
    }
}

// MARK: - NextEpisodeContent

/// Body of the Next Episode card.
private struct NextEpisodeContent: View {

    let episode: EpisodeSummary

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = TMDBImage.still(episode.stillPath, size: .w300) {
                EpisodeStillView(url: url, width: 120)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(episode.pointer.label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.headline)
                if let airText {
                    Text(airText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if !episode.overview.isEmpty {
                    Text(episode.overview)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        let name = episode.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? "Episode \(episode.episodeNumber)" : name
    }

    /// "Tomorrow · Oct 3, 2026", or just the full date when the relative form is already a date.
    private var airText: String? {
        guard let date = episode.airDate?.startOfDay() else { return nil }
        let relative = Formatters.relativeAirDate(date)
        let full = Formatters.shortDate(date)
        if relative.contains(where: { $0.isNumber }) {
            return full
        }
        return "\(relative) · \(full)"
    }
}

// MARK: - ProgressCardContent

/// Body of the Progress card for a show in the library.
private struct ProgressCardContent: View {

    let item: MediaItem
    let onMarkNext: () -> Void
    let onUndo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(headline)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            if let fraction = item.progressFraction {
                ProgressView(value: fraction)
                    .tint(isCaughtUp ? Color.green : Color.accentColor)
                    .accessibilityLabel("Episodes watched")
                    .accessibilityValue(countText ?? "")
                if let countText {
                    Text(countText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            buttons
        }
    }

    private var buttons: some View {
        HStack(spacing: 12) {
            Button(action: onMarkNext) {
                Label("Mark Next Watched", systemImage: "checkmark.circle")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canMarkNext)
            Button(action: onUndo) {
                Label("Undo", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(!item.progress.isStarted)
        }
    }

    // MARK: Derived

    private var isCaughtUp: Bool {
        item.progress.isStarted && item.nextUp == nil
    }

    private var headline: String {
        if isCaughtUp { return "You're caught up" }
        if item.progress.isStarted { return "You're on \(item.progress.label)" }
        return "Not started"
    }

    private var detail: String? {
        if let next = item.nextUp {
            var text = "Up next: \(next.label)"
            if let pointer = item.nextEpisodePointer, let airDate = item.nextEpisodeAirDate, pointer == next {
                text += " · airs \(Formatters.relativeAirDate(airDate))"
            }
            return text
        }
        if isCaughtUp { return "No unwatched episodes" }
        return nil
    }

    private var countText: String? {
        guard let total = item.episodeTotal, total > 0 else { return nil }
        return "\(item.watchedEpisodeCount) of \(total) episodes"
    }

    /// The next episode can be marked unless TMDB says it has not aired yet.
    private var canMarkNext: Bool {
        guard let next = item.nextUp else { return false }
        if let pointer = item.nextEpisodePointer, let airDate = item.nextEpisodeAirDate, pointer == next {
            return airDate <= Date.now
        }
        return true
    }
}

// MARK: - DetailEntryRow

/// One labeled row of the Details card.
private struct DetailEntryRow: View {

    let entry: DetailEntry

    var body: some View {
        LabeledContent {
            switch entry.value {
            case .text(let text):
                Text(text)
                    .multilineTextAlignment(.trailing)
            case .link(let title, let url):
                Link(title, destination: url)
                    .lineLimit(1)
            }
        } label: {
            Text(entry.label)
        }
        .padding(.vertical, 10)
    }
}

// MARK: - DetailPlaceholder

/// Redacted stand-in for the detail layout while the first load is in flight.
private struct DetailPlaceholder: View {

    let backdropHeight: CGFloat

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                Rectangle()
                    .fill(.quaternary)
                    .frame(height: backdropHeight)
                    .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 20) {
                    HStack(alignment: .bottom, spacing: 16) {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 110, height: 165)
                            .padding(.top, -40)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Placeholder title")
                                .font(.title2.bold())
                            Text("A tagline placeholder")
                                .font(.subheadline)
                            Text("2024 · 2 seasons · 8.1")
                                .font(.subheadline)
                        }
                    }
                    .padding(.horizontal, 16)
                    cardShape(height: 52)
                    cardShape(height: 140)
                    cardShape(height: 220)
                }
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
        }
        .scrollDisabled(true)
        .ignoresSafeArea(edges: .top)
        .redacted(reason: .placeholder)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }

    private func cardShape(height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(.quaternary)
            .frame(height: height)
            .padding(.horizontal, 16)
    }
}

// MARK: - Previews

#Preview("Library show") {
    NavigationStack {
        MediaDetailView(reference: .library(PreviewData.sampleShow.id))
    }
    .modelContainer(PreviewData.container)
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
}

#Preview("Custom show") {
    NavigationStack {
        MediaDetailView(reference: .library(PreviewData.sampleCustomShow.id))
    }
    .modelContainer(PreviewData.container)
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
}

#Preview("TMDB movie") {
    NavigationStack {
        MediaDetailView(reference: .tmdb(id: 693134, kind: .movie))
    }
    .modelContainer(PreviewData.container)
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
}
