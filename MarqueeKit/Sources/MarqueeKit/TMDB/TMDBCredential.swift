import Foundation

// MARK: - TMDBCredential

/// A TMDB credential: either a v4 "API Read Access Token" (a long JWT containing ".")
/// sent as `Authorization: Bearer <token>`, or a v3 API key (32 hex characters)
/// sent as the `api_key` query item.
public enum TMDBCredential: Hashable, Sendable {
    case bearer(String)
    case apiKey(String)

    /// The raw secret string.
    public var value: String {
        switch self {
        case .bearer(let token): return token
        case .apiKey(let key): return key
        }
    }

    /// `true` when the secret is non-empty.
    public var isUsable: Bool { !value.isEmpty }

    /// Picks the credential type from the shape of `raw`. Whitespace is trimmed; empty input yields `nil`.
    public static func detect(_ raw: String) -> TMDBCredential? {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        if lowercased.hasPrefix("bearer ") || lowercased == "bearer" {
            trimmed = String(trimmed.dropFirst("bearer".count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains(".") {
            return .bearer(trimmed)
        }
        if isHexKey(trimmed) {
            return .apiKey(trimmed)
        }
        // Unknown shape: long opaque strings are almost certainly tokens, short ones keys.
        return trimmed.count > 40 ? .bearer(trimmed) : .apiKey(trimmed)
    }

    // MARK: Helpers

    private static func isHexKey(_ string: String) -> Bool {
        guard string.count == 32 else { return false }
        let hexDigits = CharacterSet(charactersIn: "0123456789abcdefABCDEF")
        return string.unicodeScalars.allSatisfy { hexDigits.contains($0) }
    }
}
