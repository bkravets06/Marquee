import SwiftUI

// MARK: - RegionPicker

/// A searchable list of ISO 3166-1 regions. The selection feeds TMDB's
/// `region` parameter for In Theaters and Coming Soon.
struct RegionPicker: View {

    @Binding private var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    init(selection: Binding<String>) {
        _selection = selection
    }

    // MARK: Body

    var body: some View {
        let regions = filteredRegions
        return List {
            ForEach(regions) { region in
                regionRow(region)
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if regions.isEmpty {
                ContentUnavailableView.search(text: searchText)
            }
        }
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search Regions"
        )
        .navigationTitle("Region")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Rows

    private func regionRow(_ region: Entry) -> some View {
        let isSelected = region.code == selection
        return Button {
            select(region)
        } label: {
            HStack {
                Text(region.name)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                }
            }
        }
        .accessibilityAddTraits(isSelected ? AccessibilityTraits.isSelected : [])
    }

    private func select(_ region: Entry) {
        if selection != region.code {
            selection = region.code
        }
        dismiss()
    }

    // MARK: Data

    /// One selectable region.
    private struct Entry: Identifiable, Hashable {
        let code: String
        let name: String
        var id: String { code }
    }

    /// Two-letter ISO regions with a localized name, sorted by that name.
    /// Numeric UN M.49 areas, macro regions and pseudo regions are dropped.
    private static let allEntries: [Entry] = {
        let excluded: Set<String> = ["EU", "EZ", "UN", "QO", "ZZ", "XA", "XB"]
        let locale = Locale.current
        var seen: Set<String> = []
        var entries: [Entry] = []
        for region in Locale.Region.isoRegions {
            let code = region.identifier.uppercased()
            guard code.count == 2, code.allSatisfy({ $0.isLetter }) else { continue }
            guard !excluded.contains(code), !seen.contains(code) else { continue }
            guard let name = locale.localizedString(forRegionCode: code), !name.isEmpty, name != code else { continue }
            seen.insert(code)
            entries.append(Entry(code: code, name: name))
        }
        return entries.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }()

    private var filteredRegions: [Entry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return RegionPicker.allEntries }
        return RegionPicker.allEntries.filter { entry in
            entry.name.localizedCaseInsensitiveContains(query)
                || entry.code.localizedCaseInsensitiveContains(query)
        }
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        RegionPicker(selection: .constant("US"))
    }
    .environment(AppEnvironment.shared)
    .modelContainer(PreviewData.container)
}
