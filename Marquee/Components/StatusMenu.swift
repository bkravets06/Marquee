import SwiftUI
import MarqueeKit

// MARK: - StatusMenu
//
// Menu for choosing an item's library status (Watching / Watchlist / Watched)
// with an optional destructive "Remove from Library" entry.
//
// API:
//   enum StatusMenuStyle { case prominent, compact }
//   StatusMenu(current: WatchStatus?, style: StatusMenuStyle = .prominent,
//              onSelect: @escaping (WatchStatus) -> Void, onRemove: (() -> Void)? = nil)
//
// `current == nil` means "not in the library": the prominent style reads
// "Add to Library" and the compact style shows `plus.circle`. When an item is
// in the library the prominent style shows the current status name, its symbol
// and a chevron, and the compact style shows the filled status symbol.
// `onSelect` is only called when a different status is chosen. Callers own
// haptics (`.sensoryFeedback`) and persistence.

/// Visual variants of `StatusMenu`.
enum StatusMenuStyle {
    /// Full-width large button, for detail screens.
    case prominent
    /// Icon-only button, for rows and cards.
    case compact
}

/// Library status picker presented as a system `Menu`.
struct StatusMenu: View {

    let current: WatchStatus?
    let style: StatusMenuStyle
    let onSelect: (WatchStatus) -> Void
    let onRemove: (() -> Void)?

    init(
        current: WatchStatus?,
        style: StatusMenuStyle = .prominent,
        onSelect: @escaping (WatchStatus) -> Void,
        onRemove: (() -> Void)? = nil
    ) {
        self.current = current
        self.style = style
        self.onSelect = onSelect
        self.onRemove = onRemove
    }

    // MARK: Body

    var body: some View {
        switch style {
        case .prominent:
            prominentMenu
        case .compact:
            compactMenu
        }
    }

    // MARK: Prominent

    @ViewBuilder
    private var prominentMenu: some View {
        if current == nil {
            prominentBase
                .buttonStyle(.borderedProminent)
        } else {
            prominentBase
                .buttonStyle(.bordered)
        }
    }

    private var prominentBase: some View {
        Menu {
            menuItems
        } label: {
            prominentLabel
                .frame(maxWidth: .infinity)
        }
        .menuStyle(.button)
        .controlSize(.large)
        .accessibilityLabel(accessibilityText)
    }

    private var prominentLabel: some View {
        HStack(spacing: 6) {
            if let current {
                Label(current.displayName, systemImage: current.symbolName)
                Image(systemName: "chevron.down")
                    .imageScale(.small)
                    .fontWeight(.bold)
            } else {
                Label("Add to Library", systemImage: "plus")
                    .foregroundStyle(.black)
            }
        }
        .font(.body.weight(.semibold))
    }

    // MARK: Compact

    private var compactMenu: some View {
        Menu {
            menuItems
        } label: {
            Image(systemName: compactSymbolName)
                .imageScale(.large)
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .accessibilityLabel(accessibilityText)
    }

    private var compactSymbolName: String {
        guard let current else { return "plus.circle" }
        return current.symbolName + ".fill"
    }

    // MARK: Shared menu content

    @ViewBuilder
    private var menuItems: some View {
        Picker("Status", selection: selection) {
            ForEach(WatchStatus.allCases) { status in
                Label(status.displayName, systemImage: status.symbolName)
                    .tag(Optional(status))
            }
        }
        .pickerStyle(.inline)

        if let onRemove {
            Divider()
            Button("Remove from Library", systemImage: "trash", role: .destructive, action: onRemove)
        }
    }

    private var selection: Binding<WatchStatus?> {
        Binding<WatchStatus?>(
            get: { current },
            set: { newValue in
                guard let newValue, newValue != current else { return }
                onSelect(newValue)
            }
        )
    }

    private var accessibilityText: String {
        guard let current else { return "Add to Library" }
        return "Status: \(current.displayName)"
    }
}

// MARK: - Preview

#Preview("Status menus") {
    VStack(spacing: 24) {
        StatusMenu(current: nil, onSelect: { _ in })
        StatusMenu(current: .watching, onSelect: { _ in }, onRemove: {})
        HStack(spacing: 32) {
            StatusMenu(current: nil, style: .compact, onSelect: { _ in })
            StatusMenu(current: .watchlist, style: .compact, onSelect: { _ in }, onRemove: {})
            StatusMenu(current: .watched, style: .compact, onSelect: { _ in })
        }
    }
    .padding()
}
