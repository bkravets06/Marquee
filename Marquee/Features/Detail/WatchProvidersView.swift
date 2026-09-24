import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - WatchProvidersView

/// "Where to Watch" card on the detail screen: the streaming, rental and
/// purchase options TMDB lists (data from JustWatch) for the user's region.
/// Renders nothing for custom titles and while nothing has been requested.
struct WatchProvidersView: View {

    let model: DetailModel
    /// ISO 3166-1 region code to show offers for, e.g. "US" (`AppSettings.region`).
    let region: String
    /// Reloads the offers after a failed request.
    let onRetry: () -> Void
    /// Opens Settings so the user can pick another region.
    let onChangeRegion: () -> Void

    init(model: DetailModel, region: String, onRetry: @escaping () -> Void, onChangeRegion: @escaping () -> Void) {
        self.model = model
        self.region = region
        self.onRetry = onRetry
        self.onChangeRegion = onChangeRegion
    }

    // MARK: Body

    var body: some View {
        if model.supportsWatchProviders {
            card
        }
    }

    /// Loaded offers stay on screen through a reload or a failed refresh;
    /// the placeholder and error states only appear before the first success.
    @ViewBuilder
    private var card: some View {
        if model.watchProviders != nil {
            loadedCard
        } else if model.isLoadingWatchProviders {
            loadingCard
        } else if let message = model.watchProvidersErrorMessage {
            DetailCard("Where to Watch") {
                ErrorRetryView(message: message, retry: onRetry)
            }
        }
    }

    // MARK: Loaded

    @ViewBuilder
    private var loadedCard: some View {
        let offers = model.watchProviders(in: region)
        let groups = offers?.groups ?? []
        if let offers, !groups.isEmpty {
            DetailCard("Where to Watch") {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in
                        offerGroup(group)
                    }
                    footer(link: offers.link)
                }
            }
        } else {
            DetailCard("Where to Watch") {
                unavailableContent
            }
        }
    }

    /// One kind of offer ("Stream", "Rent", ...) with its providers scrolling
    /// edge to edge of the card, which pads its content by 16pt.
    private func offerGroup(_ group: WatchOfferGroup) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(group.kind.displayName)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(group.providers) { provider in
                        ProviderChip(provider: provider)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .padding(.horizontal, -16)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(group.kind.displayName): \(providerNames(in: group))")
    }

    private func providerNames(in group: WatchOfferGroup) -> String {
        group.providers.map { $0.name }.joined(separator: ", ")
    }

    private func footer(link: URL?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let link {
                Link("All Options on TMDB", destination: link)
                    .font(.subheadline.weight(.semibold))
            }
            attribution
        }
    }

    // MARK: Unavailable

    private var unavailableContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Not available to stream, rent or buy in \(regionName).")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Change Region", action: onChangeRegion)
                .font(.subheadline.weight(.semibold))
            attribution
        }
    }

    // MARK: Loading

    /// Redacted stand-in for one offer group while the first request is in flight.
    private var loadingCard: some View {
        DetailCard("Where to Watch") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Stream")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.quaternary)
                            .frame(width: 48, height: 48)
                    }
                }
            }
            .redacted(reason: .placeholder)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Loading where to watch")
        }
    }

    // MARK: Attribution

    /// TMDB's terms require crediting JustWatch wherever provider data is shown.
    private var attribution: some View {
        Text("Availability in \(regionName), provided by JustWatch.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    private var regionName: String {
        Locale.current.localizedString(forRegionCode: region) ?? region
    }
}

// MARK: - ProviderChip

/// A provider's square logo with its name beneath, sized for a horizontal row.
private struct ProviderChip: View {

    let provider: WatchProvider

    @ScaledMetric(relativeTo: .caption2) private var logoSize: CGFloat = 48

    private static let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)

    var body: some View {
        VStack(spacing: 6) {
            logo
                .frame(width: logoSize, height: logoSize)
                .clipShape(ProviderChip.shape)
                .overlay(ProviderChip.shape.strokeBorder(Color(.separator), lineWidth: 0.5))
            Text(provider.name)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .frame(width: max(64, logoSize + 16))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(provider.name)
    }

    @ViewBuilder
    private var logo: some View {
        if let url = TMDBImage.logo(provider.logoPath, size: .w154) {
            AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.25))) { phase in
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
        ZStack {
            Rectangle()
                .fill(.quaternary)
            Image(systemName: "play.rectangle")
                .font(.system(size: logoSize * 0.4))
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Previews

#Preview("Where to Watch") {
    let model = DetailModel(reference: .tmdb(id: 95396, kind: .show))
    model.show = PreviewData.sampleShowDetails
    model.watchProviders = PreviewData.sampleWatchProviders
    return NavigationStack {
        ScrollView {
            WatchProvidersView(model: model, region: "US", onRetry: {}, onChangeRegion: {})
                .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
    .modelContainer(PreviewData.container)
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
}

#Preview("Not available") {
    let model = DetailModel(reference: .tmdb(id: 95396, kind: .show))
    model.show = PreviewData.sampleShowDetails
    model.watchProviders = PreviewData.sampleWatchProviders
    return NavigationStack {
        ScrollView {
            WatchProvidersView(model: model, region: "FR", onRetry: {}, onChangeRegion: {})
                .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
    .modelContainer(PreviewData.container)
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
}

#Preview("Failed") {
    let model = DetailModel(reference: .tmdb(id: 95396, kind: .show))
    model.show = PreviewData.sampleShowDetails
    model.watchProvidersErrorMessage = "The Internet connection appears to be offline."
    return NavigationStack {
        ScrollView {
            WatchProvidersView(model: model, region: "US", onRetry: {}, onChangeRegion: {})
                .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }
    .modelContainer(PreviewData.container)
    .environment(AppEnvironment.shared)
    .environment(Navigator.shared)
}
