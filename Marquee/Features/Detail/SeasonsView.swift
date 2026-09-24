import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - SeasonsView

/// "Seasons" card on the detail screen: one row per regular season, each
/// pushing `EpisodeListView`. Renders nothing for movies, custom shows and
/// shows without season data.
struct SeasonsView: View {

    let model: DetailModel

    init(model: DetailModel) {
        self.model = model
    }

    private var seasons: [SeasonInfo] {
        model.regularSeasons
    }

    var body: some View {
        if let showID = model.tmdbID, model.kind == .show, !seasons.isEmpty {
            DetailCard("Seasons") {
                VStack(spacing: 0) {
                    ForEach(Array(seasons.enumerated()), id: \.element.id) { index, info in
                        if index > 0 {
                            Divider()
                                .padding(.leading, 60)
                        }
                        SeasonRow(showID: showID, info: info, item: model.item)
                    }
                }
            }
        }
    }
}

// MARK: - SeasonRow

/// A season row: small poster, name, "10 episodes · 2024", progress and a chevron.
private struct SeasonRow: View {

    let showID: Int
    let info: SeasonInfo
    let item: MediaItem?

    var body: some View {
        NavigationLink {
            EpisodeListView(showID: showID, season: info, item: item)
        } label: {
            HStack(spacing: 16) {
                PosterView(url: TMDBImage.poster(info.posterPath, size: .w92), kind: .show, width: 44, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                trailing
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    // MARK: Derived

    /// "10 episodes · 2024"
    private var subtitle: String {
        var parts: [String] = []
        parts.append(info.episodeCount == 1 ? "1 episode" : "\(info.episodeCount) episodes")
        if let year = info.airDate?.year {
            parts.append(String(year))
        }
        return parts.joined(separator: " · ")
    }

    /// Episodes of this season at or before the library pointer.
    private var watchedInSeason: Int {
        guard let item else { return 0 }
        let progress = item.progress
        if progress.season > info.number {
            return info.episodeCount
        }
        if progress.season == info.number {
            return min(max(progress.episode, 0), info.episodeCount)
        }
        return 0
    }

    private var isSeasonWatched: Bool {
        info.episodeCount > 0 && watchedInSeason >= info.episodeCount
    }

    @ViewBuilder
    private var trailing: some View {
        if item != nil {
            if isSeasonWatched {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityLabel("Watched")
            } else if watchedInSeason > 0 {
                Text("\(watchedInSeason) of \(info.episodeCount)")
                    .font(.subheadline)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("\(watchedInSeason) of \(info.episodeCount) watched")
            }
        }
    }
}

// MARK: - Preview

#Preview("Seasons") {
    let model = DetailModel(reference: .tmdb(id: 95396, kind: .show))
    model.show = PreviewData.sampleShowDetails
    model.item = PreviewData.sampleShow
    return NavigationStack {
        ScrollView {
            SeasonsView(model: model)
                .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
    .modelContainer(PreviewData.container)
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
}
