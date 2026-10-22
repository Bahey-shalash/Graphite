import SwiftUI
import GraphiteCore

/// Obsidian's Groups panel in the graph's settings: each group is a search and a color, and
/// the files it matches take its color. The first group a file matches wins.
struct GraphColorGroupsSection: View {
    let groups: [GraphColorGroup]
    let addGroup: () -> Void
    let update: (GraphColorGroup) -> Void
    let removeGroup: (String) -> Void

    var body: some View {
        Section {
            ForEach(groups) { group in
                GraphColorGroupRow(group: group, update: update, remove: { removeGroup(group.id) })
            }
            Button("New Group", systemImage: "plus.circle", action: addGroup)
        } header: {
            Text("Groups")
        } footer: {
            Text("Notes a group's search matches take its color, as in the filter: words of the path, path:\"Courses/\", tag:#name.")
        }
    }
}

/// One group: its color, its search and a button that removes it. The search is edited
/// here and each change is kept as it is typed.
private struct GraphColorGroupRow: View {
    let group: GraphColorGroup
    let update: (GraphColorGroup) -> Void
    let remove: () -> Void
    @State private var query: String

    init(group: GraphColorGroup, update: @escaping (GraphColorGroup) -> Void, remove: @escaping () -> Void) {
        self.group = group
        self.update = update
        self.remove = remove
        _query = State(initialValue: group.query)
    }

    var body: some View {
        HStack(spacing: 10) {
            ColorPicker("Group Color", selection: color, supportsOpacity: false)
                .labelsHidden()
            TextField("Search", text: $query, prompt: Text("tag:#course or path:\"Courses/\""))
                #if canImport(UIKit)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onChange(of: query) {
                    var changed = group
                    changed.query = query
                    update(changed)
                }
            Button("Remove Group", systemImage: "minus.circle", role: .destructive, action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
        }
    }

    /// The group's color; a color picked here is kept as `#rrggbb`.
    private var color: Binding<Color> {
        Binding(get: { group.colorHex.flatMap(Color.init(graphiteHex:)) ?? .gray },
                set: { pickedColor in
                    var changed = group
                    changed.colorHex = pickedColor.sRGBHex
                    update(changed)
                })
    }
}
