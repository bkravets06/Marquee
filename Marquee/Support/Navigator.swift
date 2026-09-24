import Foundation
import Observation

// MARK: - AppTab

/// Top-level tabs of `RootView`.
enum AppTab: Hashable {
    case discover
    case library
    case search
}

// MARK: - LibraryRoute

/// Navigation destinations pushed inside the Library tab.
enum LibraryRoute: Hashable {
    case item(UUID)
}

// MARK: - Navigator

/// App-wide navigation state, shared so notification taps can deep link.
@MainActor
@Observable
final class Navigator {

    static let shared = Navigator()

    /// The selected tab.
    var tab: AppTab = .discover

    /// The Library tab's navigation path.
    var libraryPath: [LibraryRoute] = []

    /// A library item that should be shown as soon as `RootView` can react.
    var pendingItemID: UUID?

    init() {}

    /// Requests that the item with `itemID` be shown in the Library tab.
    /// `RootView` observes `pendingItemID` and performs the navigation.
    func open(itemID: UUID) {
        pendingItemID = itemID
    }
}
