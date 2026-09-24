import SwiftUI

// MARK: - ErrorRetryView
//
// Compact inline error row: warning symbol, a footnote message and a bordered
// "Retry" button. Meant for a failed carousel section or list; wrap it in a
// card background if the surrounding page needs one.
//
// API:
//   ErrorRetryView(message: String, retry: @escaping () -> Void)

/// Inline error message with a retry button.
struct ErrorRetryView: View {

    let message: String
    let retry: () -> Void

    init(message: String, retry: @escaping () -> Void) {
        self.message = message
        self.retry = retry
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .accessibilityHidden(true)
            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Preview

#Preview("Error retry") {
    VStack(spacing: 16) {
        ErrorRetryView(message: "Your TMDB API key was rejected.", retry: {})
        ErrorRetryView(message: "The Internet connection appears to be offline. Check your connection and try again.", retry: {})
    }
    .padding()
}
