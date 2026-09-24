import SwiftUI

// MARK: - RatingLabel
//
// Star + one-decimal TMDB rating ("8.1"). Renders nothing when the rating is
// zero (TMDB's "no votes yet"). Inherits the surrounding font; defaults to the
// secondary foreground style, which callers can override.
//
// API:
//   RatingLabel(voteAverage: Double)

/// Compact star rating.
struct RatingLabel: View {

    let voteAverage: Double

    init(voteAverage: Double) {
        self.voteAverage = voteAverage
    }

    var body: some View {
        if voteAverage > 0 {
            HStack(spacing: 3) {
                Image(systemName: "star.fill")
                    .imageScale(.small)
                Text(ratingText)
                    .monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rated \(ratingText) out of 10")
        }
    }

    private var ratingText: String {
        Formatters.rating(voteAverage)
    }
}

// MARK: - Preview

#Preview("Ratings") {
    VStack(alignment: .leading, spacing: 12) {
        RatingLabel(voteAverage: 8.4)
        RatingLabel(voteAverage: 6.25)
            .font(.title3)
        HStack {
            Text("Hidden when zero:")
            RatingLabel(voteAverage: 0)
        }
    }
    .padding()
}
