import SwiftUI

// MARK: - Theme

/// Shared styling decisions that are not expressed by the asset catalog.
extension ShapeStyle where Self == Color {

    /// Foreground for content drawn on top of the Marquee Gold accent, such as
    /// the labels of `.borderedProminent` buttons. The accent is light in both
    /// appearances, so a dark label keeps the contrast ratio above 4.5:1 where
    /// the system's default white label would not.
    static var onAccent: Color { .black }
}
