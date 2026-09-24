import Foundation
import Security

// MARK: - Keychain

/// Minimal generic-password keychain wrapper used for the TMDB credential.
enum Keychain {

    /// Errors surfaced by `set(_:for:)`.
    enum KeychainError: Error, LocalizedError {
        case encodingFailed
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "The value could not be stored."
            case .unexpectedStatus(let status):
                return "Keychain error \(status)."
            }
        }
    }

    /// Keychain service name shared by every Marquee item.
    static let service = "com.bjkravets.marquee"

    // MARK: Read

    /// The stored string for `key`, or `nil` when missing or unreadable.
    static func string(for key: String) -> String? {
        var query = baseQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    // MARK: Write

    /// Stores `value` under `key`, replacing any existing item.
    static func set(_ value: String, for key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        delete(key)

        var attributes = baseQuery(for: key)
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    /// Removes the item stored under `key`, if any.
    static func delete(_ key: String) {
        let query = baseQuery(for: key)
        _ = SecItemDelete(query as CFDictionary)
    }

    // MARK: Private

    private static func baseQuery(for key: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
    }
}
