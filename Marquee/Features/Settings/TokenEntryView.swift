import SwiftUI
import UIKit
import MarqueeKit

// MARK: - TokenEntryView

/// Enter, validate and store a TMDB credential.
///
/// Pushed from Settings it renders as a `Form`; with `embedded == true` it is a
/// plain stack that onboarding drops into its own page. The key is checked
/// against TMDB with a throwaway client *before* it is persisted, so a bad key
/// never replaces a working one.
struct TokenEntryView: View {

    @Environment(AppEnvironment.self) private var appEnvironment
    @Environment(\.dismiss) private var dismiss

    private let embedded: Bool
    private let onSaved: (() -> Void)?

    @State private var rawKey = ""
    @State private var isRevealed = false
    @State private var isValidating = false
    @State private var errorMessage: String?
    @State private var didSave = false
    @State private var isConfirmingRemoval = false
    @State private var successCount = 0
    @State private var errorCount = 0
    @FocusState private var isFieldFocused: Bool

    private static let apiSettingsURL = URL(string: "https://www.themoviedb.org/settings/api")

    init(embedded: Bool = false, onSaved: (() -> Void)? = nil) {
        self.embedded = embedded
        self.onSaved = onSaved
    }

    // MARK: Body

    var body: some View {
        Group {
            if embedded {
                embeddedLayout
            } else {
                formLayout
            }
        }
        .sensoryFeedback(.success, trigger: successCount)
        .sensoryFeedback(.error, trigger: errorCount)
        .confirmationDialog("Remove TMDB Key?", isPresented: $isConfirmingRemoval, titleVisibility: .visible) {
            Button("Remove Key", role: .destructive, action: removeKey)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Discover and Search stop working until a new key is added. Your library is not affected.")
        }
    }

    // MARK: Form layout (Settings)

    private var formLayout: some View {
        Form {
            keySection
            actionSection
            helpSection
            if appEnvironment.hasCredentials {
                removeSection
            }
        }
        .navigationTitle("TMDB API Key")
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
    }

    private var keySection: some View {
        Section {
            keyField
            HStack {
                Button("Paste", systemImage: "doc.on.clipboard", action: pasteFromClipboard)
                Spacer()
                Button(revealTitle, systemImage: revealSymbol) {
                    isRevealed.toggle()
                }
            }
            .buttonStyle(.borderless)
        } header: {
            Text("API Read Access Token")
        } footer: {
            Text(explanation)
        }
    }

    private var actionSection: some View {
        Section {
            Button(action: validateAndSave) {
                HStack {
                    Text("Validate & Save")
                    Spacer()
                    if isValidating {
                        ProgressView()
                    }
                }
            }
            .disabled(!canSubmit)
        } footer: {
            statusText
        }
    }

    private var helpSection: some View {
        Section {
            if let url = TokenEntryView.apiSettingsURL {
                Link(destination: url) {
                    Label("Get a TMDB API Key", systemImage: "safari")
                }
            }
        } footer: {
            Text("Sign in to TMDB, open Settings › API and copy the API Read Access Token.")
        }
    }

    private var removeSection: some View {
        Section {
            Button("Remove Key", role: .destructive) {
                isConfirmingRemoval = true
            }
        }
    }

    // MARK: Embedded layout (Onboarding)

    private var embeddedLayout: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                keyField
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(
                        Color(uiColor: .secondarySystemBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                    )
                HStack {
                    Button("Paste", systemImage: "doc.on.clipboard", action: pasteFromClipboard)
                    Spacer()
                    Button(revealTitle, systemImage: revealSymbol) {
                        isRevealed.toggle()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            statusText
                .font(.footnote)

            Button(action: validateAndSave) {
                HStack(spacing: 8) {
                    if isValidating {
                        ProgressView()
                    }
                    Text("Validate & Save")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!canSubmit)

            if appEnvironment.hasCredentials {
                Button("Remove Key", role: .destructive) {
                    isConfirmingRemoval = true
                }
                .frame(maxWidth: .infinity)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(explanation)
                    .foregroundStyle(.secondary)
                if let url = TokenEntryView.apiSettingsURL {
                    Link("Get a TMDB API Key", destination: url)
                }
            }
            .font(.footnote)
        }
    }

    // MARK: Shared pieces

    private var keyField: some View {
        Group {
            if isRevealed {
                TextField("Paste your token or key", text: $rawKey)
            } else {
                SecureField("Paste your token or key", text: $rawKey)
            }
        }
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .keyboardType(.asciiCapable)
        .focused($isFieldFocused)
        .submitLabel(.go)
        .onSubmit(validateAndSave)
        .accessibilityLabel("TMDB API key")
        .onChange(of: rawKey) { _, _ in
            errorMessage = nil
            if didSave {
                didSave = false
            }
        }
    }

    @ViewBuilder
    private var statusText: some View {
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        } else if didSave {
            Label("Connected to TMDB.", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        } else if appEnvironment.hasCredentials {
            Text("A TMDB key is already saved on this device. Enter a new one to replace it.")
                .foregroundStyle(.secondary)
        } else {
            Text("Your key is checked with TMDB before it is saved.")
                .foregroundStyle(.secondary)
        }
    }

    private var explanation: String {
        "Marquee uses your own free TMDB account. Sign in at themoviedb.org, open Settings › API and copy the API Read Access Token (recommended). A v3 API key also works. The key stays in your Keychain and is only ever sent to TMDB."
    }

    private var revealTitle: String {
        isRevealed ? "Hide" : "Show"
    }

    private var revealSymbol: String {
        isRevealed ? "eye.slash" : "eye"
    }

    private var trimmedKey: String {
        rawKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedKey.isEmpty && !isValidating
    }

    // MARK: Actions

    private func pasteFromClipboard() {
        let pasted = UIPasteboard.general.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pasted.isEmpty else {
            fail("There is no text on the clipboard.")
            return
        }
        rawKey = pasted
    }

    private func validateAndSave() {
        guard canSubmit else { return }
        isFieldFocused = false
        let raw = trimmedKey
        guard let credential = TMDBCredential.detect(raw) else {
            fail(AppError.invalidCredential.errorDescription ?? "That does not look like a TMDB key.")
            return
        }
        isValidating = true
        errorMessage = nil
        didSave = false
        Task {
            await validate(raw: raw, credential: credential)
        }
    }

    /// Probes TMDB with a throwaway client; only a key TMDB accepts is stored.
    private func validate(raw: String, credential: TMDBCredential) async {
        defer { isValidating = false }
        let probe = TMDBClient(credential: credential, region: appEnvironment.settings.region)
        do {
            let accepted = try await probe.validateCredentials()
            guard accepted else {
                fail(TMDBError.unauthorized.errorDescription ?? "Your TMDB API key was rejected.")
                return
            }
            try appEnvironment.setCredential(raw)
        } catch let error as TMDBError {
            fail(error.errorDescription ?? "TMDB could not verify that key.")
            return
        } catch {
            fail(error.localizedDescription)
            return
        }
        succeed()
    }

    private func succeed() {
        errorMessage = nil
        didSave = true
        successCount += 1
        onSaved?()
        guard !embedded else { return }
        Task {
            try? await Task.sleep(for: .seconds(0.8))
            dismiss()
        }
    }

    private func fail(_ message: String) {
        didSave = false
        errorMessage = message
        errorCount += 1
    }

    private func removeKey() {
        appEnvironment.clearCredential()
        rawKey = ""
        didSave = false
        errorMessage = nil
    }
}

// MARK: - Previews

#Preview("Form") {
    NavigationStack {
        TokenEntryView()
    }
    .environment(AppEnvironment.shared)
    .modelContainer(PreviewData.container)
}

#Preview("Embedded") {
    ScrollView {
        TokenEntryView(embedded: true)
            .padding(24)
    }
    .environment(AppEnvironment.shared)
    .modelContainer(PreviewData.container)
}
