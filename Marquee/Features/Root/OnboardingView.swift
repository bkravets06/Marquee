import SwiftUI
import SwiftData
import UserNotifications

// MARK: - OnboardingView

/// First-launch flow shown as a full-screen cover by `RootView`: a welcome
/// page, an optional TMDB key page and a notification permission page.
/// Finishing (or skipping) sets `settings.hasCompletedOnboarding`, which is
/// what dismisses the cover.
struct OnboardingView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var page = 0
    @State private var isRequestingNotifications = false

    private static let lastPage = 2

    init() {}

    // MARK: Body

    var body: some View {
        TabView(selection: $page) {
            welcomePage
                .tag(0)
            connectPage
                .tag(1)
            notificationsPage
                .tag(2)
        }
        .tabViewStyle(.page(indexDisplayMode: .always))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .task {
            await appEnvironment.notifications.refreshAuthorizationStatus()
        }
    }

    // MARK: Pages

    private var welcomePage: some View {
        pageContainer {
            heroSymbol("sparkles.tv")
            VStack(spacing: 12) {
                Text("Welcome to Marquee")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Keep track of the shows and movies you’re watching, all in one place.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 20) {
                FeatureRow(
                    symbol: "sparkles",
                    title: "Discover",
                    description: "Browse what’s trending, airing today and in theaters, powered by TMDB."
                )
                FeatureRow(
                    symbol: "checkmark.circle",
                    title: "Track Progress",
                    description: "Keep your place in every show, episode by episode, and always know what’s up next."
                )
                FeatureRow(
                    symbol: "bell.badge",
                    title: "Get Notified",
                    description: "Get a reminder on the day a new episode of a show you follow comes out."
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } footer: {
            primaryButton("Continue", action: advance)
        }
    }

    private var connectPage: some View {
        pageContainer {
            heroSymbol("key.fill")
            VStack(spacing: 12) {
                Text("Connect to TMDB")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Discover and Search use The Movie Database. Paste your free API key or read access token to browse the catalog. You can also add it later in Settings.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            TokenEntryView(embedded: true, onSaved: { advance() })
                .frame(maxWidth: .infinity)
        } footer: {
            if appEnvironment.hasCredentials {
                primaryButton("Continue", action: advance)
            } else {
                secondaryButton("Skip for Now", action: advance)
            }
        }
    }

    private var notificationsPage: some View {
        pageContainer {
            heroSymbol("bell.badge")
            VStack(spacing: 12) {
                Text("Never Miss an Episode")
                    .font(.largeTitle.bold())
                    .multilineTextAlignment(.center)
                Text("Marquee can remind you on the day a new episode airs for the shows you follow. Reminders are scheduled on this device and never leave it.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            if notificationStatus == .denied {
                Text("Notifications are currently turned off for Marquee. You can allow them any time in the Settings app.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        } footer: {
            if notificationStatus == .notDetermined {
                primaryButton("Enable Notifications", isBusy: isRequestingNotifications, action: enableNotifications)
                secondaryButton("Not Now", action: finish)
            } else {
                primaryButton("Get Started", action: finish)
            }
        }
    }

    // MARK: Building blocks

    /// Scrollable, vertically centred page content with buttons pinned below.
    /// The bottom padding leaves room for the page indicator.
    private func pageContainer<Content: View, Footer: View>(
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) -> some View {
        let inner = content()
        let buttons = footer()
        return VStack(spacing: 0) {
            GeometryReader { proxy in
                ScrollView {
                    VStack(spacing: 28) {
                        inner
                    }
                    .frame(maxWidth: 520)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 32)
                    .frame(maxWidth: .infinity, minHeight: proxy.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            VStack(spacing: 12) {
                buttons
            }
            .frame(maxWidth: 520)
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 44)
        }
    }

    private func heroSymbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 64, weight: .medium))
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }

    private func primaryButton(_ title: String, isBusy: Bool = false, action: @escaping @MainActor () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView()
                }
                Text(title)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(.onAccent)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isBusy)
    }

    private func secondaryButton(_ title: String, action: @escaping @MainActor () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(.borderless)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
    }

    private var notificationStatus: UNAuthorizationStatus {
        appEnvironment.notifications.authorizationStatus
    }

    // MARK: Actions

    private func advance() {
        withAnimation {
            page = min(page + 1, OnboardingView.lastPage)
        }
    }

    private func enableNotifications() {
        guard !isRequestingNotifications else { return }
        isRequestingNotifications = true
        Task {
            let granted = await appEnvironment.notifications.requestAuthorization()
            if granted {
                let store = LibraryStore(context: modelContext)
                await appEnvironment.notifications.sync(
                    items: store.showsWithNotificationsEnabled(),
                    settings: appEnvironment.settings
                )
            }
            isRequestingNotifications = false
            finish()
        }
    }

    /// Marks onboarding complete; `RootView`'s cover binding closes the sheet.
    private func finish() {
        appEnvironment.settings.hasCompletedOnboarding = true
        dismiss()
    }
}

// MARK: - FeatureRow

/// One "what Marquee does" row on the welcome page.
private struct FeatureRow: View {

    let symbol: String
    let title: String
    let description: String

    @ScaledMetric(relativeTo: .title2) private var iconWidth: CGFloat = 36

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Preview

#Preview {
    let settings = AppSettings(defaults: UserDefaults(suiteName: "preview.onboarding") ?? .standard)
    settings.hasCompletedOnboarding = false
    return OnboardingView()
        .environment(AppEnvironment(settings: settings))
        .environment(Navigator.shared)
        .modelContainer(PreviewData.container)
}
