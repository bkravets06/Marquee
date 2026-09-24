import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - ProgressBadge
//
// Capsule summarising where the user is in an item:
//   shows  -> "S2 E5" (last watched), "Not started", or "Caught up"
//   movies -> "Watched" when watched; otherwise nothing is rendered
//
// API:
//   ProgressBadge(item: MediaItem)
//   ProgressBadge.text(for: MediaItem) -> String?   // the same label as plain text, for subtitles

/// Progress capsule for a library item.
struct ProgressBadge: View {

    let item: MediaItem

    init(item: MediaItem) {
        self.item = item
    }

    // MARK: State

    /// What the badge should say for `item`.
    enum ProgressState: Equatable {
        case notStarted
        case inProgress(String)
        case caughtUp
        case watched
    }

    /// Classifies `item` for display.
    static func state(for item: MediaItem) -> ProgressState? {
        guard item.isShow else {
            return item.status == .watched ? .watched : nil
        }
        if item.status == .watched {
            return .caughtUp
        }
        let progress = item.progress
        guard progress.isStarted else {
            return .notStarted
        }
        if item.nextUp == nil, let total = item.episodeTotal, total > 0 {
            return .caughtUp
        }
        return .inProgress(progress.label)
    }

    /// Plain-text label matching what the badge shows, or `nil` when the badge
    /// would render nothing.
    static func text(for item: MediaItem) -> String? {
        guard let state = state(for: item) else { return nil }
        return label(for: state)
    }

    private static func label(for state: ProgressState) -> String {
        switch state {
        case .notStarted:
            return "Not started"
        case .inProgress(let label):
            return label
        case .caughtUp:
            return "Caught up"
        case .watched:
            return "Watched"
        }
    }

    // MARK: Body

    var body: some View {
        if let state = ProgressBadge.state(for: item) {
            badge(text: ProgressBadge.label(for: state), tint: tint(for: state))
        }
    }

    private func badge(text: String, tint: Color) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.14), in: Capsule())
            .accessibilityLabel("Progress: \(text)")
    }

    private func tint(for state: ProgressState) -> Color {
        switch state {
        case .notStarted:
            return .secondary
        case .inProgress:
            return .accentColor
        case .caughtUp, .watched:
            return .green
        }
    }
}

// MARK: - Preview

#Preview("Progress badges") {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(PreviewData.items) { item in
            HStack {
                Text(item.title)
                Spacer()
                ProgressBadge(item: item)
            }
        }
    }
    .padding()
    .modelContainer(PreviewData.container)
}
