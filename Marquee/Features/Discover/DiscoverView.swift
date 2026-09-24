import SwiftUI
import SwiftData
import MarqueeKit

// MARK: - DiscoverView

/// The Discover tab: TMDB carousels (trending, airing, in theaters, popular)
/// with See All grids, a Settings sheet from the toolbar, and a prompt to
/// connect TMDB when no credential is configured.
struct DiscoverView: View {

    @Environment(AppEnvironment.self) private var appEnvironment

    @State private var model = DiscoverModel()
    @State private var isShowingSettings = false

    init() {}

    // MARK: Body

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Discover")
                .navigationDestination(for: MediaReference.self) { reference in
                    MediaDetailView(reference: reference)
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        settingsButton
                    }
                }
                .sheet(isPresented: $isShowingSettings) {
                    SettingsView()
                }
        }
        .task(id: loadKey) {
            await loadIfNeeded()
        }
    }

    @ViewBuilder
    private var content: some View {
        if appEnvironment.client == nil {
            noCredentialsView
        } else if model.allSectionsFailed {
            failureView
        } else {
            sectionList
        }
    }

    // MARK: Sections

    private var sectionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(DiscoverSectionKind.allCases) { section in
                    carousel(for: section)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, 24)
        }
        .refreshable {
            await refresh()
        }
    }

    private func carousel(for section: DiscoverSectionKind) -> some View {
        let state = model.state(for: section)
        return MediaCarousel(
            title: section.title,
            state: state,
            onRetry: { retry(section) },
            seeAll: { SeeAllView(section: section, initialState: state) }
        )
    }

    // MARK: Toolbar

    private var settingsButton: some View {
        Button("Settings", systemImage: "gearshape") {
            isShowingSettings = true
        }
    }

    // MARK: Empty states

    private var noCredentialsView: some View {
        ContentUnavailableView {
            Label("Connect to TMDB", systemImage: "key.fill")
        } description: {
            Text("Add your TMDB API key or read access token to browse what’s trending, airing and in theaters.")
        } actions: {
            Button("Open Settings") {
                isShowingSettings = true
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var failureView: some View {
        ContentUnavailableView {
            Label("Unable to Load", systemImage: "exclamationmark.triangle")
        } description: {
            Text(model.firstErrorMessage ?? "Something went wrong while talking to TMDB.")
        } actions: {
            Button("Retry") {
                Task {
                    await refresh()
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    // MARK: Loading

    /// Identity of the `.task`: it restarts when a credential appears or
    /// disappears and when the region (which feeds In Theaters / Coming Soon) changes.
    private struct LoadKey: Hashable {
        let hasClient: Bool
        let region: String
    }

    private var loadKey: LoadKey {
        LoadKey(hasClient: appEnvironment.client != nil, region: appEnvironment.settings.region)
    }

    private func loadIfNeeded() async {
        guard let client = appEnvironment.client else {
            model.reset()
            return
        }
        let region = appEnvironment.settings.region
        let regionChanged = model.loadedRegion != nil && model.loadedRegion != region
        model.loadedRegion = region
        await model.loadAll(client: client, force: regionChanged)
    }

    private func refresh() async {
        guard let client = appEnvironment.client else { return }
        await model.loadAll(client: client, force: true)
    }

    private func retry(_ section: DiscoverSectionKind) {
        guard let client = appEnvironment.client else { return }
        Task {
            await model.load(section: section, client: client, force: true)
        }
    }
}

// MARK: - Preview

#Preview {
    DiscoverView()
        .environment(AppEnvironment.shared)
        .environment(Navigator.shared)
        .modelContainer(PreviewData.container)
}
