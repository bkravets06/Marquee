import Foundation

// MARK: - Lenient decoding helpers

/// TMDB payloads are inconsistent: dates arrive as "", numbers and arrays go missing,
/// and strings are sometimes `null`. These helpers make DTO initializers forgiving
/// without hiding genuinely malformed payloads (ids and required containers still throw).
extension KeyedDecodingContainer {

    /// A `CivilDate` from a "YYYY-MM-DD" string. `nil` for missing, null, "", non-string or unparsable values.
    func civilDate(forKey key: Key) -> CivilDate? {
        let raw: String?
        do {
            raw = try decodeIfPresent(String.self, forKey: key)
        } catch {
            return nil
        }
        guard let string = raw else { return nil }
        return CivilDate(string)
    }

    /// A string, or `fallback` when missing, null or not a string.
    func string(forKey key: Key, fallback: String = "") -> String {
        do {
            return try decodeIfPresent(String.self, forKey: key) ?? fallback
        } catch {
            return fallback
        }
    }

    /// A non-empty string, or `nil` when missing, null, empty or not a string.
    func optionalString(forKey key: Key) -> String? {
        let raw: String?
        do {
            raw = try decodeIfPresent(String.self, forKey: key)
        } catch {
            return nil
        }
        guard let string = raw, !string.isEmpty else { return nil }
        return string
    }

    /// An integer, or `fallback` when missing or null. Accepts integral doubles.
    func int(forKey key: Key, fallback: Int = 0) -> Int {
        optionalInt(forKey: key) ?? fallback
    }

    /// An integer, or `nil` when missing or null. Accepts integral doubles.
    func optionalInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key), value.isFinite {
            return Int(value)
        }
        return nil
    }

    /// A double, or `fallback` when missing or null.
    func double(forKey key: Key, fallback: Double = 0) -> Double {
        optionalDouble(forKey: key) ?? fallback
    }

    /// A double, or `nil` when missing or null.
    func optionalDouble(forKey key: Key) -> Double? {
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    /// A boolean, or `fallback` when missing, null or not a boolean.
    func bool(forKey key: Key, fallback: Bool = false) -> Bool {
        do {
            return try decodeIfPresent(Bool.self, forKey: key) ?? fallback
        } catch {
            return fallback
        }
    }

    /// An array, or `[]` when missing or null. Malformed elements still throw.
    func array<Element: Decodable>(_ type: Element.Type, forKey key: Key) throws -> [Element] {
        try decodeIfPresent([Element].self, forKey: key) ?? []
    }
}
