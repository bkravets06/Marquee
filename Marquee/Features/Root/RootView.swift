import SwiftUI
import SwiftData

// MARK: - RootView

/// The tab bar. Each tab owns its own `NavigationStack`; onboarding is shown
/// as a full-screen cover until the user finishes or skips it.
struct RootView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(Navigator.self) private var navigator

    var body: some View {
        @Bindable var navigator = navigator
        TabView(selection: $navigator.tab) {
            Tab("Discover", systemImage: "sparkles", value: AppTab.discover) {
                DiscoverView()
            }
            Tab("Library", systemImage: "rectangle.stack", value: AppTab.library) {
                LibraryView()
            }
            Tab(value: AppTab.search, role: .search) {
                SearchView()
            }
        }
        .fullScreenCover(isPresented: onboardingPresented) {
            OnboardingView()
        }
        .onAppear(perform: handlePendingItem)
        .onChange(of: navigator.pendingItemID) { _, _ in
            handlePendingItem()
        }
    }

    // MARK: Onboarding

    /// Presented while onboarding has not been completed. Dismissing marks it done.
    private var onboardingPresented: Binding<Bool> {
        Binding(
            get: { !appEnvironment.settings.hasCompletedOnboarding },
            set: { presented in
                if !presented {
                    appEnvironment.settings.hasCompletedOnboarding = true
                }
            }
        )
    }

    // MARK: Deep links

    /// Moves to the Library tab and pushes the requested item.
    private func handlePendingItem() {
        guard let itemID = navigator.pendingItemID else { return }
        navigator.pendingItemID = nil
        navigator.tab = .library
        navigator.libraryPath = [.item(itemID)]
    }
}

// MARK: - Preview

#Preview {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "preview.root") ?? .standard)
    settings.hasCompletedOnboarding = true
    return RootView()
        .environment(AppEnvironment(settings: settings))
        .environment(Navigator())
        .modelContainer(PreviewData.container)
}
