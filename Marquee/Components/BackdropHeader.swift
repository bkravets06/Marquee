import SwiftUI
import MarqueeKit

// MARK: - BackdropHeader
//
// Full-width hero image for detail screens. It fills `height` points, crops
// the image to fit, and fades into `fadeColor` (the page background) at the
// bottom so the content below appears to rise out of the artwork.
//
// API:
//   BackdropHeader(url: URL?, height: CGFloat = 240, fadeColor: Color = Color(.systemBackground))
//
// Typical use (Detail): place it at the top of the ScrollView and add
// `.ignoresSafeArea(edges: .top)` from the call site. The view is decorative
// and hidden from accessibility.

/// Hero backdrop with a gradient fade into the page background.
struct BackdropHeader: View {

    let url: URL?
    let height: CGFloat
    let fadeColor: Color

    /// - Parameter fadeColor: The background of the page below the header,
    ///   for example `Color(.systemGroupedBackground)` on grouped screens.
    init(url: URL?, height: CGFloat = 240, fadeColor: Color = Color(.systemBackground)) {
        self.url = url
        self.height = height
        self.fadeColor = fadeColor
    }

    // MARK: Body

    var body: some View {
        Color.clear
            .frame(height: height)
            .frame(maxWidth: .infinity)
            .overlay { image }
            .clipped()
            .overlay(alignment: .bottom) { fade }
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var image: some View {
        if let url {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.3))) { phase in
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
        Rectangle()
            .fill(.quaternary)
    }

    private var fade: some View {
        LinearGradient(
            stops: [
                Gradient.Stop(color: fadeColor.opacity(0), location: 0),
                Gradient.Stop(color: fadeColor.opacity(0.55), location: 0.6),
                Gradient.Stop(color: fadeColor, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: height * 0.6)
    }
}

// MARK: - Preview

#Preview("Backdrop") {
    ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            BackdropHeader(url: TMDBImage.backdrop(PreviewData.sampleSummary.backdropPath))
            Text("Severance")
                .font(.largeTitle.bold())
                .padding(.horizontal)
            BackdropHeader(url: nil, height: 160)
        }
    }
    .ignoresSafeArea(edges: .top)
}
