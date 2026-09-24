import SwiftUI

// MARK: - GenreChips
//
// Horizontally scrolling row of genre capsules. Renders nothing when `genres`
// is empty. Duplicates are dropped so `ForEach` ids stay unique.
//
// API:
//   GenreChips(genres: [String], horizontalPadding: CGFloat = 0)
//
// `horizontalPadding` is applied as scroll content margins so the row can be
// placed edge to edge while its first chip still lines up with padded text.

/// Scrollable genre capsules.
struct GenreChips: View {

    let genres: [String]
    let horizontalPadding: CGFloat

    init(genres: [String], horizontalPadding: CGFloat = 0) {
        var seen = Set<String>()
        self.genres = genres.filter { seen.insert($0).inserted }
        self.horizontalPadding = horizontalPadding
    }

    var body: some View {
        if !genres.isEmpty {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(genres, id: \.self) { genre in
                        chip(genre)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, horizontalPadding, for: .scrollContent)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Genres: \(genres.joined(separator: ", "))")
        }
    }

    private func chip(_ genre: String) -> some View {
        Text(genre)
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemFill), in: Capsule())
    }
}

// MARK: - Preview

#Preview("Genre chips") {
    VStack(alignment: .leading, spacing: 16) {
        GenreChips(genres: ["Drama", "Mystery", "Sci-Fi & Fantasy", "Thriller", "Comedy", "Crime"], horizontalPadding: 16)
        GenreChips(genres: [])
        Text("Nothing rendered above for an empty list.")
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal)
    }
}
