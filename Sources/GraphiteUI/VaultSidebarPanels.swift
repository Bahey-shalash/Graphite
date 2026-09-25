import SwiftUI
import GraphiteCore
import GraphiteIndex

/// What the left sidebar lists, as the tabs of Obsidian's left sidebar.
enum SidebarPanel: String, CaseIterable, Identifiable {
    case files, tags, properties, bookmarks

    var id: String { rawValue }

    var title: String {
        switch self {
        case .files: "Files"
        case .tags: "Tags"
        case .properties: "Properties"
        case .bookmarks: "Bookmarks"
        }
    }

    var systemImage: String {
        switch self {
        case .files: "folder"
        case .tags: "tag"
        case .properties: "list.bullet.rectangle"
        case .bookmarks: "bookmark"
        }
    }

    /// The core plugin that provides the panel; the file list is always there.
    var plugin: CorePlugin? {
        switch self {
        case .files: nil
        case .tags: .tags
        case .properties: .properties
        case .bookmarks: .bookmarks
        }
    }
}

extension VaultListSortOrder {
    /// Obsidian's wording, such as "Tag name (A to Z)".
    func title(naming noun: String) -> String {
        switch self {
        case .nameAscending: "\(noun) name (A to Z)"
        case .nameDescending: "\(noun) name (Z to A)"
        case .frequencyDescending: "Frequency (high to low)"
        case .frequencyAscending: "Frequency (low to high)"
        }
    }
}

extension PropertyType {
    /// The names Obsidian's type menu uses.
    var title: String {
        switch self {
        case .text: "Text"
        case .multitext: "List"
        case .number: "Number"
        case .checkbox: "Checkbox"
        case .date: "Date"
        case .datetime: "Date & time"
        case .tags: "Tags"
        case .aliases: "Aliases"
        }
    }

    /// Obsidian's icons for each type.
    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .multitext: "list.bullet"
        case .number: "number"
        case .checkbox: "checkmark.square"
        case .date: "calendar"
        case .datetime: "clock"
        case .tags: "tag"
        case .aliases: "arrow.turn.up.right"
        }
    }

    /// The types a property can be given; tags and aliases belong to their own names.
    static var assignable: [PropertyType] { [.text, .multitext, .number, .checkbox, .date, .datetime] }
}

/// Per-device settings of the Tags and Properties views, kept as Obsidian keeps them in
/// its workspace rather than in the vault.
enum SidebarPanelSettingKey {
    static let panel = "sidebarPanel"
    static let tagSortOrder = "tagsViewSortOrder"
    static let showsNestedTags = "tagsViewShowsNestedTags"
    static let propertySortOrder = "propertiesViewSortOrder"
}

// MARK: Loading

/// What the Tags and Properties views list. It is loaded by the sidebar's list itself:
/// inside a `List`, a section's modifiers apply to each of its rows, so a section could
/// never load its first rows, and would load once per row after that.
@MainActor @Observable
final class VaultOverviewModel {
    var tagCounts: [TagCount] = []
    var hasLoadedTags = false
    var properties: [PropertySummary] = []
    var hasLoadedProperties = false
    /// The property whose Rename alert is shown.
    var renamedProperty: PropertySummary?
    var newPropertyName = ""
    /// The bookmark whose Rename alert is shown, and whether New Group's is.
    var renamedBookmark: Bookmark?
    var newBookmarkTitle = ""
    var isCreatingBookmarkGroup = false
    private var loadedVaultIdentifier: UUID?

    func load(_ panel: SidebarPanel, workspace: WorkspaceModel, showsNestedTags: Bool) async {
        // Another vault's lists must not show while this one's load.
        if loadedVaultIdentifier != workspace.currentVaultIdentifier {
            loadedVaultIdentifier = workspace.currentVaultIdentifier
            tagCounts = []; hasLoadedTags = false
            properties = []; hasLoadedProperties = false
        }
        do {
            switch panel {
            case .files: return
            case .bookmarks:
                // The file may have changed in Obsidian and synced.
                await workspace.reloadBookmarks()
            case .tags:
                tagCounts = try await workspace.vaultTags(nested: showsNestedTags)
                hasLoadedTags = true
            case .properties:
                properties = try await workspace.vaultProperties()
                hasLoadedProperties = true
            }
        } catch is CancellationError {
        } catch { workspace.errorMessage = error.localizedDescription }
    }
}

extension View {
    /// Obsidian's Rename for a property in the Properties view, renaming it in every note.
    func propertyRenameAlert(_ overview: VaultOverviewModel, workspace: WorkspaceModel) -> some View {
        alert("Rename Property", isPresented: Binding(get: { overview.renamedProperty != nil }, set: { isPresented in if !isPresented { overview.renamedProperty = nil } })) {
            TextField("Name", text: Binding(get: { overview.newPropertyName }, set: { name in overview.newPropertyName = name }))
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let renamedProperty = overview.renamedProperty else { return }
                let key = renamedProperty.key, name = overview.newPropertyName
                Task { await workspace.renameProperty(key, to: name) }
            }
        } message: {
            if let renamedProperty = overview.renamedProperty {
                Text("“\(renamedProperty.key)” is renamed in \(renamedProperty.fileCount == 1 ? "the note" : "all \(renamedProperty.fileCount) notes") that use it.")
            }
        }
    }
}

// MARK: Tags

/// Obsidian's Tags view: every tag in the vault with the notes using it. Tapping a tag
/// searches for it, nested tags included.
struct VaultTagsList: View {
    @Bindable var workspace: WorkspaceModel
    let overview: VaultOverviewModel
    @AppStorage(SidebarPanelSettingKey.tagSortOrder) private var sortOrder = VaultListSortOrder.frequencyDescending
    @AppStorage(SidebarPanelSettingKey.showsNestedTags) private var showsNestedTags = true
    @State private var expandedTags: Set<String> = []

    var body: some View {
        Section {
            if showsNestedTags {
                ForEach(TagTree.nodes(from: overview.tagCounts.map { count in (count.tag, count.fileCount) }, sortedBy: sortOrder)) { node in
                    TagTreeRow(node: node, expandedTags: $expandedTags, search: workspace.searchForTag)
                }
            } else {
                ForEach(sortOrder.sorted(overview.tagCounts, name: \.tag, count: \.fileCount), id: \.tag) { count in
                    TagRowLabel(title: count.tag, fileCount: count.fileCount) { workspace.searchForTag(count.tag) }
                }
            }
            if !overview.hasLoadedTags {
                ProgressView().frame(maxWidth: .infinity)
            } else if overview.tagCounts.isEmpty && workspace.hasCompletedIndexScan {
                Text("No tags in this vault yet. Write #tag in a note, or add it to the note's tags property.").foregroundStyle(.secondary)
            }
        } footer: {
            if !workspace.hasCompletedIndexScan { Text("Still reading the vault; more tags may appear.") }
        }
    }
}

private struct TagTreeRow: View {
    let node: TagTreeNode
    @Binding var expandedTags: Set<String>
    let search: (String) -> Void

    private var isExpanded: Binding<Bool> {
        Binding(get: { expandedTags.contains(node.id) }, set: { expands in
            if expands { expandedTags.insert(node.id) } else { expandedTags.remove(node.id) }
        })
    }

    var body: some View {
        if node.children.isEmpty {
            TagRowLabel(title: node.name, fileCount: node.fileCount) { search(node.tag) }
        } else {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(node.children) { child in TagTreeRow(node: child, expandedTags: $expandedTags, search: search) }
            } label: {
                TagRowLabel(title: node.name, fileCount: node.fileCount) { search(node.tag) }
            }
        }
    }
}

private struct TagRowLabel: View {
    let title: String
    let fileCount: Int
    let search: () -> Void

    var body: some View {
        Button(action: search) {
            HStack {
                Label(title, systemImage: "number").lineLimit(1)
                Spacer(minLength: 8)
                Text(fileCount, format: .number).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Searches for notes with this tag")
    }
}

// MARK: Properties

/// Obsidian's Properties view: every property in the vault with its type and the notes
/// using it. Tapping one searches for it; its menu changes its type or renames it in
/// every note.
struct VaultPropertiesList: View {
    @Bindable var workspace: WorkspaceModel
    let overview: VaultOverviewModel
    @AppStorage(SidebarPanelSettingKey.propertySortOrder) private var sortOrder = VaultListSortOrder.frequencyDescending

    var body: some View {
        Section {
            ForEach(sortOrder.sorted(overview.properties, name: \.key, count: \.fileCount)) { property in
                VaultPropertyRow(property: property) { workspace.searchForProperty(property.key) }
                    .contextMenu { menu(for: property) }
            }
            if !overview.hasLoadedProperties {
                ProgressView().frame(maxWidth: .infinity)
            } else if overview.properties.isEmpty && workspace.hasCompletedIndexScan {
                Text("No properties in this vault yet. Add them to a note from its Properties.").foregroundStyle(.secondary)
            }
        } footer: {
            if !workspace.hasCompletedIndexScan { Text("Still reading the vault; more properties may appear.") }
        }
    }

    @ViewBuilder private func menu(for property: PropertySummary) -> some View {
        Button("Search", systemImage: "magnifyingglass") { workspace.searchForProperty(property.key) }
        // Obsidian gives tags, aliases and cssclasses their types by name.
        if NoteProperties.defaultType(forKey: property.key.lowercased()) == nil {
            Picker(selection: Binding(get: { property.type }, set: { type in Task { await workspace.setPropertyType(type, forKey: property.key) } })) {
                ForEach(PropertyType.assignable) { type in Label(type.title, systemImage: type.systemImage).tag(type) }
            } label: {
                Label("Property Type", systemImage: property.type.systemImage)
            }
            .pickerStyle(.menu)
        }
        Button("Rename…", systemImage: "pencil") {
            overview.newPropertyName = property.key
            overview.renamedProperty = property
        }
    }
}

private struct VaultPropertyRow: View {
    let property: PropertySummary
    let search: () -> Void

    var body: some View {
        Button(action: search) {
            HStack {
                Label(property.key, systemImage: property.type.systemImage).lineLimit(1)
                Spacer(minLength: 8)
                Text(property.fileCount, format: .number).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("\(property.type.title). Searches for notes with this property")
    }
}

// MARK: Bookmarks

extension View {
    /// Rename for a bookmark and New Group, shared with Obsidian's Bookmarks.
    func bookmarkAlerts(_ overview: VaultOverviewModel, workspace: WorkspaceModel) -> some View {
        let title = Binding(get: { overview.newBookmarkTitle }, set: { title in overview.newBookmarkTitle = title })
        return alert("Rename Bookmark", isPresented: Binding(get: { overview.renamedBookmark != nil }, set: { isPresented in if !isPresented { overview.renamedBookmark = nil } })) {
            TextField("Name", text: title)
            Button("Cancel", role: .cancel) {}
            Button("Rename") {
                guard let bookmark = overview.renamedBookmark else { return }
                let newTitle = overview.newBookmarkTitle
                Task { await workspace.renameBookmark(bookmark, to: newTitle) }
            }
        } message: {
            Text("Leave the name empty to show the note, folder, or search itself.")
        }
        .alert("New Bookmark Group", isPresented: Binding(get: { overview.isCreatingBookmarkGroup }, set: { isPresented in overview.isCreatingBookmarkGroup = isPresented })) {
            TextField("Name", text: title)
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                let newTitle = overview.newBookmarkTitle
                Task { await workspace.addBookmarkGroup(named: newTitle) }
            }
        }
    }
}

/// Obsidian's Bookmarks view: notes (or a heading or block in one), folders, searches and
/// groups of them, from the vault's `.obsidian/bookmarks.json`.
struct VaultBookmarksList: View {
    @Bindable var workspace: WorkspaceModel
    let overview: VaultOverviewModel
    @State private var expandedGroups: Set<String> = []

    var body: some View {
        Section {
            BookmarkRows(bookmarks: workspace.bookmarks.items, workspace: workspace, overview: overview, expandedGroups: $expandedGroups)
            if workspace.bookmarks.items.isEmpty {
                Text("No bookmarks yet. Bookmark a note from its More menu, or a file or folder from its menu in Files. Bookmarks are shared with Obsidian.")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct BookmarkRows: View {
    let bookmarks: [Bookmark]
    @Bindable var workspace: WorkspaceModel
    let overview: VaultOverviewModel
    @Binding var expandedGroups: Set<String>

    var body: some View {
        // Two identical bookmarks could share an identity; their position tells them apart.
        ForEach(Array(bookmarks.enumerated()), id: \.offset) { _, bookmark in
            if bookmark.type == "group" {
                DisclosureGroup(isExpanded: Binding(get: { expandedGroups.contains(bookmark.id) }, set: { expands in
                    if expands { expandedGroups.insert(bookmark.id) } else { expandedGroups.remove(bookmark.id) }
                })) {
                    BookmarkRows(bookmarks: bookmark.children, workspace: workspace, overview: overview, expandedGroups: $expandedGroups)
                } label: {
                    Label(bookmark.displayTitle, systemImage: "rectangle.stack").lineLimit(1)
                        .contextMenu { menu(for: bookmark) }
                }
            } else {
                BookmarkRow(bookmark: bookmark, workspace: workspace)
                    .contextMenu { menu(for: bookmark) }
            }
        }
    }

    @ViewBuilder private func menu(for bookmark: Bookmark) -> some View {
        // A note no longer in the vault has nothing to open.
        if bookmark.type == "file", let path = bookmark.vaultPath, workspace.isInVault(path) {
            Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") { Task { await workspace.open(bookmark, placement: .newTab) } }
            Button(workspace.openOnOtherSideTitle, systemImage: "rectangle.split.2x1") { Task { await workspace.open(bookmark, placement: .otherGroup) } }
            Divider()
        }
        Button("Rename…", systemImage: "pencil") {
            overview.newBookmarkTitle = bookmark.title ?? ""
            overview.renamedBookmark = bookmark
        }
        Button(bookmark.type == "group" ? "Remove Group" : "Remove Bookmark", systemImage: "bookmark.slash", role: .destructive) {
            Task { await workspace.removeBookmark(bookmark) }
        }
    }
}

private struct BookmarkRow: View {
    let bookmark: Bookmark
    @Bindable var workspace: WorkspaceModel

    var body: some View {
        switch bookmark.type {
        case "file", "folder", "search":
            Button { Task { await workspace.open(bookmark) } } label: { label(subtitle: isMissing ? "Not in this vault" : nil).contentShape(Rectangle()) }
                .buttonStyle(.plain)
                .foregroundStyle(isMissing ? .secondary : .primary)
        case "url":
            if let url = bookmark.url.flatMap(URL.init(string:)) {
                Link(destination: url) { label(subtitle: nil) }.foregroundStyle(.primary)
            } else {
                label(subtitle: nil).foregroundStyle(.secondary)
            }
        default:
            // A graph or another kind Obsidian shows; kept in the file, listed here.
            label(subtitle: "Opens in Obsidian").foregroundStyle(.secondary)
        }
    }

    private func label(subtitle: String?) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.displayTitle).lineLimit(1)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
        } icon: {
            Image(systemName: systemImage)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var isMissing: Bool {
        guard bookmark.type == "file" || bookmark.type == "folder" else { return false }
        return bookmark.vaultPath.map { path in !workspace.isInVault(path) } ?? true
    }

    private var systemImage: String {
        switch bookmark.type {
        case "file":
            if bookmark.subpath?.contains("^") == true { return "square.dashed" }
            if bookmark.subpath != nil { return "number" }
            return bookmark.vaultPath.map { path in DocumentKind(path: path) == .pdf ? "doc.richtext" : "doc.text" } ?? "doc.text"
        case "folder": return "folder"
        case "search": return "magnifyingglass"
        case "url": return "globe"
        case "graph": return "point.3.connected.trianglepath.dotted"
        default: return "bookmark"
        }
    }
}
