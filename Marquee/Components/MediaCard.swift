import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - MediaCard
//
// Poster card for carousels and grids: poster, two-line title and a caption
// such as "2024 · Show". All children are combined into one accessibility
// element. Wrap it in a `NavigationLink`/`Button` to make it tappable.
//
// API:
//   MediaCard(summary: MediaSummary, width: CGFloat = 120)
//   MediaCard(item: MediaItem, width: CGFloat = 120)

/// Poster card with title and caption.
struct MediaCard: View {

    let poster: PosterView
    let title: String
    let caption: String
    let width: CGFloat

    // MARK: Init

    init(summary: MediaSummary, width: CGFloat = 120) {
        self.poster = PosterView(summary: summary, width: width)
        self.title = summary.title
        self.caption = MediaCard.caption(year: summary.year, kind: summary.kind)
        self.width = width
    }

    init(item: MediaItem, width: CGFloat = 120) {
        self.poster = PosterView(item: item, width: width)
        self.title = item.title
        self.caption = MediaCard.caption(year: item.year, kind: item.kind)
        self.width = width
    }

    /// "2024 · Show", or just "Show" when the year is unknown.
    static func caption(year: Int?, kind: MediaKind) -> String {
        if let year {
            return "\(String(year)) · \(kind.displayName)"
        }
        return kind.displayName
    }

    // MARK: Body

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            poster
            Text(title)
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(width: width, alignment: .leading)
        // Fixed-width card; larger text breaks words apart.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview("Media cards") {
    ScrollView(.horizontal) {
        HStack(alignment: .top, spacing: 12) {
            ForEach(PreviewData.sampleSummaries, id: \.key) { summary in
                MediaCard(summary: summary)
            }
            MediaCard(item: PreviewData.sampleCustomShow)
        }
        .padding()
    }
    .modelContainer(PreviewData.container)
}
