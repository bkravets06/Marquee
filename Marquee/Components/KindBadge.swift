import SwiftUI
import MarqueeKit

// MARK: - KindBadge
//
// Tiny capsule reading "Show" or "Movie".
//
// API:
//   KindBadge(kind: MediaKind)

/// Small capsule label for a media kind.
struct KindBadge: View {

    let kind: MediaKind

    init(kind: MediaKind) {
        self.kind = kind
    }

    var body: some View {
        Text(kind.displayName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(.secondarySystemFill), in: Capsule())
            .accessibilityLabel(kind.displayName)
    }
}

// MARK: - Preview

#Preview("Kind badges") {
    HStack(spacing: 12) {
        KindBadge(kind: .show)
        KindBadge(kind: .movie)
    }
    .padding()
}
