import Foundation

// MARK: - ImageCache

/// Configures the shared URL cache so poster and backdrop images fetched by
/// `AsyncImage` are kept in memory and on disk.
enum ImageCache {

    /// Memory budget for cached responses (64 MB).
    static let memoryCapacity = 64 * 1024 * 1024

    /// Disk budget for cached responses (256 MB).
    static let diskCapacity = 256 * 1024 * 1024

    /// Installs the cache as `URLCache.shared`. Call once at launch, before
    /// any image request is made.
    static func configure() {
        URLCache.shared = URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            directory: nil
        )
    }
}
