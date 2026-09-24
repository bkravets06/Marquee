import SwiftUI
import MarqueeKit

// MARK: - EpisodeRow

/// One episode in a season list: still thumbnail, "E5 · Name", air date and
/// runtime, a two-line overview and a watched indicator. The row is a button
/// when `onToggle` is provided and the episode has aired.
struct EpisodeRow: View {

    let episode: EpisodeSummary
    let isWatched: Bool
    let isAired: Bool
    let onToggle: (() -> Void)?

    init(episode: EpisodeSummary, isWatched: Bool, isAired: Bool, onToggle: (() -> Void)? = nil) {
        self.episode = episode
        self.isWatched = isWatched
        self.isAired = isAired
        self.onToggle = onToggle
    }

    // MARK: Body

    var body: some View {
        if let onToggle, isAired {
            Button(action: onToggle) {
                content
            }
            .accessibilityHint(isWatched ? "Marks this episode as not watched." : "Marks episodes as watched through this one.")
        } else {
            content
        }
    }

    private var content: some View {
        HStack(alignment: .center, spacing: 12) {
            EpisodeStillView(url: TMDBImage.still(episode.stillPath, size: .w300), width: 96)
            textBlock
            Spacer(minLength: 4)
            statusIcon
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isWatched ? AccessibilityTraits.isSelected : AccessibilityTraits())
    }

    private var textBlock: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
            if let detailText {
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if !episode.overview.isEmpty {
                Text(episode.overview)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.leading)
    }

    @ViewBuilder
    private var statusIcon: some View {
        if !isAired {
            Image(systemName: "clock")
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Not yet aired")
        } else if onToggle != nil || isWatched {
            Image(systemName: isWatched ? "checkmark.circle.fill" : "circle")
                .imageScale(.large)
                .foregroundStyle(isWatched ? Color.accentColor : Color.secondary)
                .accessibilityLabel(isWatched ? "Watched" : "Not watched")
        }
    }

    // MARK: Text

    /// "E5 · Name", or "Episode 5" when TMDB has no name yet.
    private var title: String {
        let name = episode.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty {
            return "Episode \(episode.episodeNumber)"
        }
        return "E\(episode.episodeNumber) · \(name)"
    }

    /// "Oct 3, 2026 · 48m" for aired episodes, "Airs Tomorrow · 48m" otherwise.
    private var detailText: String? {
        var parts: [String] = []
        if let date = episode.airDate?.startOfDay() {
            if isAired {
                parts.append(Formatters.shortDate(date))
            } else {
                parts.append("Airs \(Formatters.relativeAirDate(date))")
            }
        }
        if let runtime = episode.runtime, runtime > 0 {
            parts.append(Formatters.runtime(minutes: runtime))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

// MARK: - EpisodeStillView

/// 16:9 episode still with a rounded clip and a quaternary placeholder.
struct EpisodeStillView: View {

    let url: URL?
    let width: CGFloat

    init(url: URL?, width: CGFloat) {
        self.url = url
        self.width = width
    }

    private var height: CGFloat { width * 9 / 16 }

    var body: some View {
        image
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var image: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let loaded):
                    loaded
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                case .empty:
                    placeholder
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: "tv")
                .font(.system(size: max(12, width * 0.18)))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Preview

#Preview("Episode rows") {
    let today = CivilDate.today()
    let calendar = Calendar.current
    let nextWeek = calendar.date(byAdding: .day, value: 6, to: .now).map { CivilDate($0) } ?? today
    let aired = EpisodeSummary(
        id: 1,
        name: "Woe's Hollow",
        overview: "The team goes on a mysterious retreat and learns more than they bargained for.",
        seasonNumber: 2,
        episodeNumber: 4,
        airDate: CivilDate(year: 2025, month: 2, day: 7),
        runtime: 51
    )
    let unaired = EpisodeSummary(
        id: 2,
        name: "Trojan's Horse",
        overview: "The team mourns a loss and makes a startling discovery.",
        seasonNumber: 2,
        episodeNumber: 5,
        airDate: nextWeek,
        runtime: 48
    )
    return NavigationStack {
        List {
            EpisodeRow(episode: aired, isWatched: true, isAired: true, onToggle: {})
            EpisodeRow(episode: aired, isWatched: false, isAired: true, onToggle: {})
            EpisodeRow(episode: unaired, isWatched: false, isAired: false, onToggle: nil)
            EpisodeRow(episode: aired, isWatched: false, isAired: true, onToggle: nil)
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Season 2")
        .navigationBarTitleDisplayMode(.inline)
    }
}
