import Foundation
import Observation
import MarqueeKit

// MARK: - AppError

/// App-level errors surfaced to the UI.
enum AppError: Error, LocalizedError {
    case invalidCredential

    var errorDescription: String? {
        switch self {
        case .invalidCredential:
            return "That does not look like a TMDB API Read Access Token or API key."
        }
    }
}

// MARK: - AppEnvironment

/// Process-wide dependencies: the TMDB client, user settings and the
/// notification manager. Injected into the view tree with `.environment(_:)`.
@MainActor
@Observable
final class AppEnvironment {

    /// The instance used by the running app.
    static let shared = AppEnvironment()

    /// Keychain account under which the TMDB credential is stored.
    static let credentialKey = "tmdb.credential"

    /// The TMDB client, or `nil` when no credential is configured.
    var client: TMDBClient?

    let settings: AppSettings
    let notifications: NotificationManager

    /// Whether a usable TMDB credential is configured.
    var hasCredentials: Bool {
        client != nil
    }

    // MARK: Init

    init(settings: AppSettings = AppSettings()) {
        self.settings = settings
        self.notifications = NotificationManager()
        self.client = nil
        makeClient()
        observeRegion()
    }

    // MARK: Credentials

    /// Validates the credential's shape, stores it in the Keychain and
    /// rebuilds the client. Throws `AppError.invalidCredential` otherwise.
    func setCredential(_ raw: String) throws {
        guard let credential = TMDBCredential.detect(raw) else {
            throw AppError.invalidCredential
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        try Keychain.set(trimmed, for: AppEnvironment.credentialKey)
        client = makeClient(credential: credential)
    }

    /// Removes the stored credential and drops the client.
    func clearCredential() {
        Keychain.delete(AppEnvironment.credentialKey)
        client = nil
    }

    /// Builds `client` from the Keychain credential, or in DEBUG builds from
    /// the `TMDB_ACCESS_TOKEN` environment variable. Sets `client` to `nil`
    /// when neither is available.
    func makeClient() {
        guard let credential = storedCredential() else {
            client = nil
            return
        }
        client = makeClient(credential: credential)
    }

    /// Recreates the client so it picks up the current region and language.
    func rebuildClient() {
        makeClient()
    }

    // MARK: Private

    private func storedCredential() -> TMDBCredential? {
        if let raw = Keychain.string(for: AppEnvironment.credentialKey),
           let credential = TMDBCredential.detect(raw) {
            return credential
        }
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment["TMDB_ACCESS_TOKEN"],
           let credential = TMDBCredential.detect(raw) {
            return credential
        }
        #endif
        return nil
    }

    private func makeClient(credential: TMDBCredential) -> TMDBClient {
        TMDBClient(credential: credential, language: languageTag, region: settings.region)
    }

    /// "en-US" style tag TMDB accepts: device language plus the chosen region.
    private var languageTag: String {
        let languageCode = Locale.current.language.languageCode?.identifier ?? "en"
        return "\(languageCode)-\(settings.region)"
    }

    /// Rebuilds the client whenever `settings.region` changes.
    private func observeRegion() {
        withObservationTracking {
            _ = settings.region
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.rebuildClient()
                self.observeRegion()
            }
        }
    }
}
