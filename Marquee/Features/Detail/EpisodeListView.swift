import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - EpisodeListView

/// Episodes of one season, fetched from TMDB. When a library `item` is given,
/// tapping an aired episode sets the show's progress to it (tapping the
/// current episode again steps back one), and a toolbar menu marks the whole
/// season watched or unwatched. Without an item the list is read-only.
struct EpisodeListView: View {

    let showID: Int
    let season: SeasonInfo
    let item: MediaItem?

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext

    @State private var episodes: [EpisodeSummary] = []
    @State private var seasonOverview = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var loadAttempt = 0
    @State private var markCount = 0
    @State private var unmarkCount = 0

    init(showID: Int, season: SeasonInfo, item: MediaItem?) {
        self.showID = showID
        self.season = season
        self.item = item
    }

    private var store: LibraryStore {
        LibraryStore(context: modelContext)
    }

    // MARK: Body

    var body: some View {
        List {
            if isLoading && episodes.isEmpty {
                placeholderSection
            } else if !episodes.isEmpty {
                if let errorMessage {
                    Section {
                        ErrorRetryView(message: errorMessage) {
                            loadAttempt += 1
                        }
                    }
                }
                episodesSection
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            emptyOverlay
        }
        .navigationTitle(season.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            toolbarContent
        }
        .task(id: loadAttempt) {
            await load()
        }
        .sensoryFeedback(.success, trigger: markCount)
        .sensoryFeedback(.impact(weight: .light), trigger: unmarkCount)
    }

    // MARK: Sections

    private var episodesSection: some View {
        Section {
            ForEach(episodes) { episode in
                EpisodeRow(
                    episode: episode,
                    isWatched: isWatched(episode),
                    isAired: isAired(episode),
                    onToggle: toggleAction(for: episode)
                )
            }
        } header: {
            if !seasonOverview.isEmpty {
                Text(seasonOverview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .textCase(nil)
                    .padding(.bottom, 4)
            }
        }
    }

    private var placeholderSection: some View {
        Section {
            ForEach(0..<placeholderCount, id: \.self) { _ in
                EpisodeRow(episode: EpisodeListView.placeholderEpisode, isWatched: false, isAired: true, onToggle: nil)
                    .redacted(reason: .placeholder)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Loading episodes")
            }
        }
    }

    private var placeholderCount: Int {
        min(max(season.episodeCount, 3), 8)
    }

    private static let placeholderEpisode = EpisodeSummary(
        id: 0,
        name: "Episode title placeholder",
        overview: "A short overview of the episode that spans two lines of placeholder text.",
        seasonNumber: 1,
        episodeNumber: 1,
        airDate: CivilDate(year: 2024, month: 1, day: 1),
        runtime: 45
    )

    @ViewBuilder
    private var emptyOverlay: some View {
        if episodes.isEmpty && !isLoading {
            if let errorMessage {
                ContentUnavailableView {
                    Label("Unable to Load Episodes", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                } actions: {
                    Button("Try Again") {
                        loadAttempt += 1
                    }
                    .buttonStyle(.borderedProminent)
                }
            } else {
                ContentUnavailableView(
                    "No Episodes",
                    systemImage: "tv",
                    description: Text("TMDB hasn't listed any episodes for this season yet.")
                )
            }
        }
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if item != nil {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Mark Season Watched", systemImage: "checkmark.circle") {
                        markSeasonWatched()
                    }
                    .disabled(lastAiredEpisode == nil || isSeasonFullyWatched)
                    Button("Mark Season Unwatched", systemImage: "circle") {
                        markSeasonUnwatched()
                    }
                    .disabled(!hasWatchedAnyInSeason)
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
                .disabled(episodes.isEmpty)
            }
        }
    }

    // MARK: Loading

    private func load() async {
        guard let client = appEnvironment.client else {
            isLoading = false
            errorMessage = TMDBError.missingCredentials.errorDescription
            useFallbackEpisodesIfNeeded()
            return
        }
        isLoading = true
        errorMessage = nil
        do {
            let details = try await client.season(showID: showID, number: season.number)
            episodes = details.episodes.sorted { $0.episodeNumber < $1.episodeNumber }
            seasonOverview = details.overview.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            if Task.isCancelled {
                isLoading = false
                return
            }
            if let tmdbError = error as? TMDBError {
                errorMessage = tmdbError.errorDescription ?? "Something went wrong while talking to TMDB."
            } else {
                errorMessage = error.localizedDescription
            }
            useFallbackEpisodesIfNeeded()
        }
        isLoading = false
    }

    /// Without TMDB data, numbered placeholder episodes still let the user
    /// track progress from the season's known episode count.
    private func useFallbackEpisodesIfNeeded() {
        guard episodes.isEmpty, season.episodeCount > 0 else { return }
        episodes = (1...season.episodeCount).map { number in
            EpisodeSummary(
                id: -number,
                name: "",
                overview: "",
                seasonNumber: season.number,
                episodeNumber: number
            )
        }
    }

    // MARK: Episode state

    private func isWatched(_ episode: EpisodeSummary) -> Bool {
        guard let item else { return false }
        return item.progress >= episode.pointer
    }

    /// Episodes with an unknown air date are treated as aired so they stay markable.
    private func isAired(_ episode: EpisodeSummary) -> Bool {
        guard let airDate = episode.airDate else { return true }
        return airDate <= CivilDate.today()
    }

    private func toggleAction(for episode: EpisodeSummary) -> (() -> Void)? {
        guard item != nil, isAired(episode) else { return nil }
        return { toggle(episode) }
    }

    /// Seasons used for pointer arithmetic; falls back to this season alone.
    private func seasonsForMath(_ item: MediaItem) -> [SeasonInfo] {
        let known = item.seasons
        return known.isEmpty ? [season] : known
    }

    private var lastAiredEpisode: EpisodeSummary? {
        episodes.filter { isAired($0) }.max { $0.pointer < $1.pointer }
    }

    private var isSeasonFullyWatched: Bool {
        guard let item, let last = lastAiredEpisode else { return false }
        return item.progress >= last.pointer
    }

    private var hasWatchedAnyInSeason: Bool {
        guard let item else { return false }
        let progress = item.progress
        if progress.season > season.number { return true }
        return progress.season == season.number && progress.episode >= 1
    }

    // MARK: Actions

    /// Sets progress to `episode`, or steps back one when it is already the current episode.
    private func toggle(_ episode: EpisodeSummary) {
        guard let item else { return }
        let pointer = episode.pointer
        if item.progress == pointer {
            let previous = NextUp.previous(before: pointer, in: seasonsForMath(item))
            store.setProgress(item, to: previous)
            unmarkCount += 1
        } else {
            store.setProgress(item, to: pointer)
            markCount += 1
        }
    }

    /// Moves progress to the last episode of this season that has aired.
    private func markSeasonWatched() {
        guard let item, let last = lastAiredEpisode else { return }
        store.setProgress(item, to: last.pointer)
        markCount += 1
    }

    /// Moves progress back to the end of the previous season.
    private func markSeasonUnwatched() {
        guard let item, let first = episodes.min(by: { $0.pointer < $1.pointer }) else { return }
        let previous = NextUp.previous(before: first.pointer, in: seasonsForMath(item))
        store.setProgress(item, to: previous)
        unmarkCount += 1
    }
}

// MARK: - Preview

#Preview("Season episodes") {
    NavigationStack {
        EpisodeListView(
            showID: 95396,
            season: SeasonInfo(number: 2, name: "Season 2", episodeCount: 10, airDate: CivilDate(year: 2025, month: 1, day: 17)),
            item: PreviewData.sampleShow
        )
    }
    .modelContainer(PreviewData.container)
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
}
