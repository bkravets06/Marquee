import SwiftUI
import SwiftData
import UIKit
import MarqueeKit

// MARK: - PosterView
//
// A 2:3 poster thumbnail with the app's standard rounded corners and shadow.
//
// API:
//   PosterView(url: URL?, imageData: Data? = nil, kind: MediaKind, width: CGFloat, cornerRadius: CGFloat = 10)
//   PosterView(item: MediaItem, width: CGFloat, cornerRadius: CGFloat = 10)      // custom poster data, else TMDB URL
//   PosterView(summary: MediaSummary, width: CGFloat, cornerRadius: CGFloat = 10)
//   PosterView.posterSize(forWidth:) -> TMDBImage.PosterSize                     // shared size heuristic
//
// Height is always `width * 1.5`. `imageData` wins over `url` when it decodes.
// The placeholder (quaternary fill + the kind's SF Symbol) shows while loading,
// on failure and when there is no image at all. The view carries no
// accessibility label; wrap it in a control or combine it with its title.

/// Poster thumbnail for a show or movie.
struct PosterView: View {

    let url: URL?
    let imageData: Data?
    let kind: MediaKind
    let width: CGFloat
    let cornerRadius: CGFloat

    // MARK: Init

    init(url: URL?, imageData: Data? = nil, kind: MediaKind, width: CGFloat, cornerRadius: CGFloat = 10) {
        self.url = url
        self.imageData = imageData
        self.kind = kind
        self.width = width
        self.cornerRadius = cornerRadius
    }

    /// Poster for a library item: the user-supplied image when present,
    /// otherwise the TMDB poster sized for `width`.
    init(item: MediaItem, width: CGFloat, cornerRadius: CGFloat = 10) {
        self.init(
            url: item.posterURL(size: PosterView.posterSize(forWidth: width)),
            imageData: item.customPosterData,
            kind: item.kind,
            width: width,
            cornerRadius: cornerRadius
        )
    }

    /// Poster for a catalog row.
    init(summary: MediaSummary, width: CGFloat, cornerRadius: CGFloat = 10) {
        self.init(
            url: TMDBImage.poster(summary.posterPath, size: PosterView.posterSize(forWidth: width)),
            imageData: nil,
            kind: summary.kind,
            width: width,
            cornerRadius: cornerRadius
        )
    }

    // MARK: Sizing

    /// TMDB poster size that stays sharp on a 3x display for a poster
    /// `width` points wide.
    static func posterSize(forWidth width: CGFloat) -> TMDBImage.PosterSize {
        if width <= 60 { return .w185 }
        if width <= 120 { return .w342 }
        if width <= 200 { return .w500 }
        return .w780
    }

    private var height: CGFloat { width * 1.5 }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    // MARK: Body

    var body: some View {
        content
            .frame(width: width, height: height)
            .clipShape(shape)
            .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
    }

    @ViewBuilder
    private var content: some View {
        if let uiImage = decodedImage {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
        } else if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
                switch phase {
                case .success(let image):
                    image
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
            Image(systemName: kind.symbolName)
                .font(.system(size: max(14, width * 0.26), weight: .regular))
                .foregroundStyle(.secondary)
        }
    }

    private var decodedImage: UIImage? {
        guard let imageData, !imageData.isEmpty else { return nil }
        return UIImage(data: imageData)
    }
}

// MARK: - Preview

#Preview("Posters") {
    HStack(alignment: .top, spacing: 16) {
        PosterView(summary: PreviewData.sampleSummary, width: 120)
        PosterView(url: nil, kind: .movie, width: 90)
        PosterView(item: PreviewData.sampleCustomShow, width: 56, cornerRadius: 6)
    }
    .padding()
    .modelContainer(PreviewData.container)
}
