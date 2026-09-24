import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - UpNextStrip

/// "Up Next": a horizontal strip of compact poster cards for shows whose next
/// episode airs soon ("Thu · S3 E4"). Renders nothing when `items` is empty.
///
/// API:
///   UpNextStrip(items: [MediaItem])   // already filtered and sorted by the caller
///
/// Each card is a `NavigationLink(value: LibraryRoute.item(id))`, so the strip
/// must sit inside the Library `NavigationStack`.
struct UpNextStrip: View {

    let items: [MediaItem]

    /// Poster width of each card.
    static let posterWidth: CGFloat = 90

    init(items: [MediaItem]) {
        self.items = items
    }

    // MARK: Body

    var body: some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Up Next")
                    .font(.title3.bold())
                    .padding(.horizontal, 20)
                    .accessibilityAddTraits(.isHeader)
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(items) { item in
                            UpNextCard(item: item)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
                .contentMargins(.horizontal, 20, for: .scrollContent)
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: Caption

    /// "Thu · S3 E4", "Today · S1 E2" or just the date/pointer when one is missing.
    static func caption(for item: MediaItem) -> String {
        var parts: [String] = []
        if let airDate = item.nextEpisodeAirDate {
            parts.append(Formatters.relativeAirDate(airDate))
        }
        if let pointer = item.nextEpisodePointer {
            parts.append(pointer.label)
        }
        return parts.isEmpty ? "New episode" : parts.joined(separator: " · ")
    }
}

// MARK: - UpNextCard

/// One poster card in the strip.
private struct UpNextCard: View {

    let item: MediaItem

    private var caption: String {
        UpNextStrip.caption(for: item)
    }

    var body: some View {
        NavigationLink(value: LibraryRoute.item(item.id)) {
            VStack(alignment: .leading, spacing: 5) {
                PosterView(item: item, width: UpNextStrip.posterWidth)
                Text(item.title)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: UpNextStrip.posterWidth, alignment: .leading)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(caption)")
        .accessibilityHint("Opens the show")
    }
}

// MARK: - Preview

#Preview("Up Next") {
    NavigationStack {
        List {
            Section {
                UpNextStrip(items: PreviewData.items.filter { $0.isShow && $0.nextEpisodeAirDate != nil })
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            Section {
                Text("Rows continue below the strip.")
                    .foregroundStyle(.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Library")
    }
    .modelContainer(PreviewData.container)
    .environment(Navigator.shared)
}
