import SwiftUI

// MARK: - Placeholders
//
// Redacted stand-ins shown while a carousel or grid is loading. They match the
// dimensions of `MediaCard` so the layout does not jump when real data lands.
//
// API:
//   MediaCardPlaceholder(width: CGFloat = 120)                              // one redacted card
//   CarouselPlaceholder(count: Int = 5, width: CGFloat = 120, horizontalPadding: CGFloat = 16)
//
// Both apply `.redacted(reason: .placeholder)` themselves and are hidden from
// accessibility; applying `.redacted` again at the call site is harmless.

// MARK: - MediaCardPlaceholder

/// A single redacted media card.
struct MediaCardPlaceholder: View {

    let width: CGFloat

    init(width: CGFloat = 120) {
        self.width = width
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.quaternary)
                .frame(width: width, height: width * 1.5)
            Text("Placeholder title text")
                .font(.subheadline.weight(.semibold))
                .lineLimit(2, reservesSpace: true)
            Text("2024 · Show")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(width: width, alignment: .leading)
        .redacted(reason: .placeholder)
        .accessibilityHidden(true)
    }
}

// MARK: - CarouselPlaceholder

/// A non-scrolling row of redacted cards, laid out like a `MediaCarousel`.
struct CarouselPlaceholder: View {

    let count: Int
    let width: CGFloat
    let horizontalPadding: CGFloat

    init(count: Int = 5, width: CGFloat = 120, horizontalPadding: CGFloat = 16) {
        self.count = max(count, 0)
        self.width = width
        self.horizontalPadding = horizontalPadding
    }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(0..<count, id: \.self) { _ in
                    MediaCardPlaceholder(width: width)
                }
            }
        }
        .scrollDisabled(true)
        .scrollIndicators(.hidden)
        .contentMargins(.horizontal, horizontalPadding, for: .scrollContent)
        .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview("Placeholders") {
    VStack(alignment: .leading, spacing: 24) {
        Text("Trending Today")
            .font(.title2.bold())
            .padding(.horizontal)
        CarouselPlaceholder()
        MediaCardPlaceholder(width: 90)
            .padding(.horizontal)
    }
}
