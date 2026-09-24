import Foundation
import MarqueeKit

// MARK: - MediaReference

/// What a detail screen should show: a TMDB title (which may or may not be in
/// the library) or a library item by its identifier.
///
/// Discover and Search push `.tmdb(id:kind:)` through
/// `NavigationLink(value:)`; the Library tab and notification deep links use
/// `.library(_:)` via `LibraryRoute`.
enum MediaReference: Hashable {
    /// A TMDB show or movie. `DetailModel` looks up a matching library item.
    case tmdb(id: Int, kind: MediaKind)
    /// A library item (TMDB-backed or custom).
    case library(UUID)
}
