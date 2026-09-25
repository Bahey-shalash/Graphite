import SwiftUI
import UniformTypeIdentifiers
import CoreTransferable
import GraphiteCore
import GraphiteIndex

/// What the sidebar asks the root view to create, and in which folder (nil: the vault's
/// "Default location for new notes").
struct CreationRequest: Identifiable {
    let kind: CreationKind
    var directory: VaultPath?
    var id: String { kind.rawValue + "|" + (directory?.rawValue ?? "") }
}

enum CreationKind: String, Identifiable {
    case note, notebook, base
    var id: String { rawValue }
    var title: String {
        switch self {
        case .note: "New Note"
        case .notebook: "New Notebook"
        case .base: "New Base"
        }
    }
    var namePrompt: String {
        switch self {
        case .note: "Note name"
        case .notebook: "Notebook name"
        case .base: "Base name"
        }
    }
}

/// A file or folder dragged within the sidebar.
struct VaultItemTransfer: Codable, Transferable {
    let path: String
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .graphiteVaultItem)
    }
}

extension UTType {
    /// Declared in the app's Info.plist; used only for drags inside Graphite.
    static let graphiteVaultItem = UTType(exportedAs: "com.graphite.study.vault-item")
}

// MARK: Sidebar

struct VaultSidebar: View {
    @Bindable var workspace: WorkspaceModel
    @Binding var creation: CreationRequest?
    @Binding var showsSettings: Bool
    @Binding var showsVaultManager: Bool
    @State private var isRootDropTargeted = false
    /// The file "Reveal Current File" scrolls to once the folders above it have listed their contents.
    @State private var fileToReveal: VaultPath?
    @FocusState private var isSearchFocused: Bool
    @Environment(\.accent) private var accent
    @AppStorage(SidebarPanelSettingKey.panel) private var storedPanel = SidebarPanel.files
    @State private var overview = VaultOverviewModel()
    @AppStorage(SidebarPanelSettingKey.tagSortOrder) private var tagSortOrder = VaultListSortOrder.frequencyDescending
    @AppStorage(SidebarPanelSettingKey.showsNestedTags) private var showsNestedTags = true
    @AppStorage(SidebarPanelSettingKey.propertySortOrder) private var propertySortOrder = VaultListSortOrder.frequencyDescending

    private var availablePanels: [SidebarPanel] {
        SidebarPanel.allCases.filter { panel in panel.plugin.map(workspace.preferences.isEnabled) ?? true }
    }

    /// The chosen panel, or the file list when its plugin was turned off.
    private var panel: SidebarPanel { availablePanels.contains(storedPanel) ? storedPanel : .files }

    var body: some View {
        ScrollViewReader { scrollProxy in
            sidebarList
                .task(id: fileToReveal) {
                    guard let fileToReveal else { return }
                    // Each folder above the file lists its contents after it expands, so the
                    // file's row exists only after a moment; scrolling to a row already in
                    // place does not move the list.
                    for _ in 0..<10 {
                        do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
                        scrollProxy.scrollTo(fileToReveal.rawValue, anchor: .center)
                    }
                    self.fileToReveal = nil
                }
        }
        .navigationTitle(workspace.title)
        .task(id: "\(panel.rawValue)-\(workspace.indexVersion)-\(workspace.propertyTypesVersion)-\(showsNestedTags)-\(workspace.currentVaultIdentifier?.uuidString ?? "")") {
            await overview.load(panel, workspace: workspace, showsNestedTags: showsNestedTags)
        }
        .propertyRenameAlert(overview, workspace: workspace)
        .bookmarkAlerts(overview, workspace: workspace)
        .searchable(text: $workspace.searchQuery, placement: .sidebar, prompt: "Search")
        .searchFocused($isSearchFocused)
        .onChange(of: workspace.searchFocusRequest) { isSearchFocused = true }
        .searchSuggestions { searchSuggestions }
        .task(id: workspace.searchQuery) {
            // An empty field shows the file tree. Results of the last query are cleared rather
            // than replaced by a search for everything, which would show under the next query.
            guard !workspace.searchQuery.isEmpty else { workspace.searchResults = []; return }
            do { try await Task.sleep(for: .milliseconds(180)); await workspace.search() } catch {}
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button("Settings", systemImage: "gearshape") { showsSettings = true }.tint(.primary)
            }
            if workspace.store != nil {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu("New", systemImage: "square.and.pencil") {
                        Button("New Note", systemImage: "doc.text") { creation = CreationRequest(kind: .note) }
                        Button("New Notebook", systemImage: "book.closed") { creation = CreationRequest(kind: .notebook) }
                        if workspace.preferences.isEnabled(.bases) { Button("New Base", systemImage: "tablecells") { creation = CreationRequest(kind: .base) } }
                        if workspace.preferences.isEnabled(.dailyNotes) {
                            Button("Today's Daily Note", systemImage: "calendar") { Task { await workspace.openDailyNote() } }
                        }
                        Divider()
                        Button("New Folder", systemImage: "folder.badge.plus") { workspace.fileSheet = .newFolder(in: workspace.newFileDirectory(nil)) }
                    }
                    .tint(.primary)
                    Menu("\(panel.title) Options", systemImage: "ellipsis.circle") { panelMenu }
                    .tint(.primary)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if workspace.store != nil && availablePanels.count > 1 {
                Picker("Sidebar", selection: Binding(get: { panel }, set: { newPanel in
                    // A search would keep hiding the chosen list.
                    workspace.searchQuery = ""
                    storedPanel = newPanel
                })) {
                    ForEach(availablePanels) { panel in Label(panel.title, systemImage: panel.systemImage).tag(panel) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16).padding(.vertical, 6)
                // Rows scroll under the picker; without a background they would show through.
                .background(.bar)
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VaultSwitcherBar(workspace: workspace) { showsVaultManager = true }
        }
    }

    /// The options of the list shown, as each Obsidian sidebar view has its own.
    @ViewBuilder private var panelMenu: some View {
        switch panel {
        case .tags:
            Picker("Sort Order", selection: $tagSortOrder) {
                ForEach(VaultListSortOrder.allCases) { sortOrder in Text(sortOrder.title(naming: "Tag")).tag(sortOrder) }
            }
            .pickerStyle(.menu)
            Toggle("Show Nested Tags", systemImage: "list.bullet.indent", isOn: $showsNestedTags)
        case .properties:
            Picker("Sort Order", selection: $propertySortOrder) {
                ForEach(VaultListSortOrder.allCases) { sortOrder in Text(sortOrder.title(naming: "Property")).tag(sortOrder) }
            }
            .pickerStyle(.menu)
        case .bookmarks:
            Button("New Group…", systemImage: "rectangle.stack.badge.plus") {
                overview.newBookmarkTitle = ""
                overview.isCreatingBookmarkGroup = true
            }
        case .files:
            FileExplorerMenuItems(workspace: workspace) { path in fileToReveal = path }
        }
    }

    private var sidebarList: some View {
        List(selection: Binding(get: { workspace.selection }, set: { newSelection in
            if let newSelection, newSelection != workspace.selection {
                #if canImport(UIKit)
                // The search field keeps its results but lets go of the keyboard, or focus
                // would later pass to the note and scroll it to its end.
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                #endif
                Task { await workspace.open(newSelection) }
            }
        })) {
            if workspace.store == nil {
                Text("Open a vault to see its files here.").foregroundStyle(.secondary)
            } else if !workspace.searchQuery.isEmpty {
                searchResults
            } else if panel == .tags {
                VaultTagsList(workspace: workspace, overview: overview)
            } else if panel == .properties {
                VaultPropertiesList(workspace: workspace, overview: overview)
            } else if panel == .bookmarks {
                VaultBookmarksList(workspace: workspace, overview: overview)
            } else if workspace.rootEntries.isEmpty {
                Text("This vault is empty. Create a note with the \(Image(systemName: "square.and.pencil")) button.").foregroundStyle(.secondary)
            } else {
                // Identified by text, so a row's implicit selection tag is not a `VaultPath`:
                // only files, which tag themselves, can be selected. A folder just folds.
                ForEach(workspace.rootEntries, id: \.path.rawValue) { entry in
                    VaultEntryRow(entry: entry, workspace: workspace) { kind, directory in creation = CreationRequest(kind: kind, directory: directory) }
                }
            }
        }
        // Folders expanded in one vault must not stay expanded, with stale contents, in the next.
        .id(workspace.currentVaultIdentifier)
        .listStyle(.sidebar)
        // Dropping on the list outside any folder or file moves the item to the vault's root.
        .dropDestination(for: VaultItemTransfer.self) { items, _ in
            moveDroppedItems(items, into: .root)
        } isTargeted: { isTargeted in isRootDropTargeted = isTargeted }
        .overlay {
            if isRootDropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(accent, lineWidth: 2).padding(4).allowsHitTesting(false)
            }
        }
    }

    private func moveDroppedItems(_ items: [VaultItemTransfer], into folder: VaultPath) -> Bool {
        let paths = items.compactMap { item in try? VaultPath(item.path) }
        guard !paths.isEmpty else { return false }
        Task { for path in paths { await workspace.move(path, into: folder) } }
        return true
    }

    @ViewBuilder private var searchResults: some View {
        Section {
            ForEach(workspace.searchResults) { result in
                SearchResultRow(result: result, workspace: workspace)
                    .tag(result.path)
                    .contextMenu {
                        Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") { Task { await workspace.open(result.path, placement: .newTab) } }
                        Button(workspace.openOnOtherSideTitle, systemImage: "rectangle.split.2x1") { Task { await workspace.open(result.path, placement: .otherGroup) } }
                    }
                    .onAppear {
                        // More results load as the list reaches its end.
                        if result.path == workspace.searchResults.last?.path { Task { await workspace.loadMoreSearchResults() } }
                    }
            }
            if workspace.searchResults.isEmpty {
                Text(workspace.searchQueryProblem ?? "No matches").foregroundStyle(.secondary)
            }
            if workspace.isLoadingMoreSearchResults {
                ProgressView().frame(maxWidth: .infinity)
            }
        } header: {
            HStack {
                Text("Results")
                Spacer()
                Menu {
                    Picker("Sort", selection: Binding(get: { workspace.preferences.searchSortOrder }, set: { sortOrder in
                        workspace.preferences.searchSortOrder = sortOrder
                        Task { await workspace.search() }
                    })) {
                        ForEach(SearchSortOrder.allCases) { sortOrder in Text(sortOrder.title).tag(sortOrder) }
                    }
                    if workspace.preferences.isEnabled(.bookmarks) {
                        Button("Bookmark This Search", systemImage: "bookmark") { Task { await workspace.bookmarkSearch(workspace.searchQuery) } }
                            .disabled(workspace.bookmarks.searchBookmark(for: workspace.searchQuery.trimmingCharacters(in: .whitespaces)) != nil)
                    }
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down").labelStyle(.iconOnly)
                }
                .textCase(nil)
            }
        }
    }

    /// Obsidian's search operators, offered while the query does not use one yet.
    @ViewBuilder private var searchSuggestions: some View {
        let query = workspace.searchQuery
        if query.isEmpty || query.hasSuffix(" ") {
            ForEach(SearchOperatorSuggestion.all) { suggestion in
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.syntax).font(.body.monospaced())
                        Text(suggestion.summary).font(.caption).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "magnifyingglass")
                }
                .searchCompletion(query + suggestion.syntax)
            }
        }
    }
}

/// The file list's sort order and folder commands, shown in the sidebar's options menu. A
/// view of its own, so opening a note or folding a folder updates these items and not the
/// whole file list.
private struct FileExplorerMenuItems: View {
    @Bindable var workspace: WorkspaceModel
    /// Scrolls the file list to a file once its folders are expanded.
    let scrollToFile: (VaultPath) -> Void

    var body: some View {
        Picker("Sort Order", selection: Binding(get: { workspace.vaultSettings.fileSortOrder }, set: { sortOrder in
            var settings = workspace.vaultSettings
            settings.fileSortOrder = sortOrder
            Task { await workspace.updateVaultSettings(settings) }
        })) {
            ForEach(FileSortOrder.allCases) { sortOrder in Text(sortOrder.title).tag(sortOrder) }
        }
        .pickerStyle(.menu)
        Button("Reveal Current File", systemImage: "scope") {
            guard let path = workspace.selection else { return }
            // Search results take the tree's place, so the search is cleared first.
            workspace.searchQuery = ""
            workspace.revealCurrentFile()
            scrollToFile(path)
        }
        .disabled(workspace.selection == nil)
        Button("Collapse All", systemImage: "arrow.down.right.and.arrow.up.left") { withAnimation(.snappy) { workspace.collapseAllFolders() } }
            .disabled(workspace.expandedFolders.isEmpty)
    }
}

/// An operator the search field suggests, with what it finds.
private struct SearchOperatorSuggestion: Identifiable {
    let syntax: String
    let summary: String
    var id: String { syntax }

    static let all = [
        SearchOperatorSuggestion(syntax: "path:", summary: "Find text in the file path"),
        SearchOperatorSuggestion(syntax: "file:", summary: "Find text in the file name"),
        SearchOperatorSuggestion(syntax: "tag:", summary: "Find notes with a tag"),
        SearchOperatorSuggestion(syntax: "line:", summary: "Find words on the same line"),
        SearchOperatorSuggestion(syntax: "section:", summary: "Find words under the same heading"),
        SearchOperatorSuggestion(syntax: "task-todo:", summary: "Find open tasks"),
        SearchOperatorSuggestion(syntax: "task-done:", summary: "Find completed tasks"),
        SearchOperatorSuggestion(syntax: "content:", summary: "Find text in note content only"),
        SearchOperatorSuggestion(syntax: "match-case:", summary: "Find text with the same capitals"),
        SearchOperatorSuggestion(syntax: "[", summary: "Find notes by property, as in [status:draft]"),
    ]
}

/// A search result: the file, then the lines that matched, each opening the note there.
private struct SearchResultRow: View {
    let result: SearchResult
    @Bindable var workspace: WorkspaceModel
    @Environment(\.accent) private var accent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                // Named by file, as in Obsidian's search; the index title is often just the first heading.
                Text(workspace.preferences.displayName(for: result.path)).lineLimit(1)
                Spacer(minLength: 4)
                if result.matchCount > 0 {
                    Text(result.matchCount.formatted()).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel(result.matchCount == 1 ? "1 matching line" : "\(result.matchCount) matching lines")
                }
            }
            if !result.path.parent.rawValue.isEmpty {
                Text(result.path.parent.rawValue).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
            }
            ForEach(result.matches, id: \.self) { match in
                Button { Task { await workspace.open(result.path, at: match) } } label: {
                    // A plain color: `.secondary` would derive from the button's accent tint.
                    Text(highlightedExcerpt(match))
                        .font(.caption).foregroundStyle(Color.secondary).lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 7).padding(.vertical, 5)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Opens the note at this line")
            }
            if result.matchCount > result.matches.count {
                Text("\((result.matchCount - result.matches.count).formatted()) more in this note").font(.caption2).foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }

    private func highlightedExcerpt(_ match: SearchMatch) -> AttributedString {
        match.highlightedExcerpt(accent: accent)
    }
}

// MARK: Files and folders

private struct VaultEntryRow: View, Equatable {
    let entry: VaultEntry
    @Bindable var workspace: WorkspaceModel
    let requestCreation: (CreationKind, VaultPath) -> Void
    @State private var children: [VaultEntry] = []
    @State private var isDropTargeted = false
    @Environment(\.accent) private var accent

    /// Rows compare by their entry alone, so an update of the list does not rebuild every
    /// row: `requestCreation` is a new closure each time but always sets the same binding,
    /// and what a row reads from the workspace is tracked by Observation on its own.
    /// SwiftUI uses this comparison without an `.equatable()` wrapper, and the wrapper must
    /// not be added: it makes a row a single view, so an expanded folder's contents are drawn
    /// inside the folder's row, centered and squeezed, instead of as rows of the list.
    nonisolated static func ==(leftRow: VaultEntryRow, rightRow: VaultEntryRow) -> Bool {
        leftRow.entry == rightRow.entry
    }

    private var isExpanded: Binding<Bool> {
        Binding(get: { workspace.expandedFolders.contains(entry.path) }, set: { expands in
            if expands { workspace.expandedFolders.insert(entry.path) } else { workspace.expandedFolders.remove(entry.path) }
        })
    }

    var body: some View {
        if entry.isDirectory {
            DisclosureGroup(isExpanded: isExpanded) {
                ForEach(children, id: \.path.rawValue) { child in
                    VaultEntryRow(entry: child, workspace: workspace, requestCreation: requestCreation)
                }
            } label: {
                // A folder is never opened as a document: tapping its name folds it, as in Obsidian.
                Button { withAnimation(.snappy) { isExpanded.wrappedValue.toggle() } } label: {
                    Label(entry.path.name, systemImage: isDropTargeted ? "folder.fill" : "folder")
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu { folderMenu }
                .draggable(VaultItemTransfer(path: entry.path.rawValue)) { dragPreview }
                .dropDestination(for: VaultItemTransfer.self) { items, _ in
                    let paths = items.compactMap { item in try? VaultPath(item.path) }.filter { path in path != entry.path }
                    guard !paths.isEmpty else { return false }
                    Task { for path in paths { await workspace.move(path, into: entry.path) } }
                    return true
                } isTargeted: { isTargeted in isDropTargeted = isTargeted }
            }
            .listRowBackground(isDropTargeted ? RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.18)) : nil)
            .task(id: "\(isExpanded.wrappedValue)-\(workspace.directoryVersion)-\(workspace.vaultSettings.fileSortOrder.rawValue)") {
                guard isExpanded.wrappedValue, let store = workspace.store else { return }
                do {
                    let listedChildren = try await store.children(of: entry.path, sortedBy: workspace.vaultSettings.fileSortOrder)
                    // Every directory refresh lists the folder again; unchanged rows are left alone.
                    if listedChildren != children { children = listedChildren }
                } catch {
                    // A folder another app removed or renamed goes away with its parent's next
                    // listing; that is not an error to report.
                    guard !Task.isCancelled, workspace.isDirectory(entry.path) else { return }
                    workspace.errorMessage = error.localizedDescription
                }
            }
        } else {
            Label {
                Text(workspace.preferences.displayName(for: entry.path)).lineLimit(1)
            } icon: {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
            .tag(entry.path)
            .contextMenu { fileMenu }
            .draggable(VaultItemTransfer(path: entry.path.rawValue)) { dragPreview }
            // A drop on a file lands in the file's folder, as in Obsidian. Without this the
            // list's own destination would take it and move the item to the vault's root.
            .dropDestination(for: VaultItemTransfer.self) { items, _ in
                let folder = entry.path.parent
                let paths = items.compactMap { item in try? VaultPath(item.path) }.filter { path in path.parent != folder }
                guard !paths.isEmpty else { return false }
                Task { for path in paths { await workspace.move(path, into: folder) } }
                return true
            }
        }
    }

    private var dragPreview: some View {
        Label(workspace.preferences.displayName(for: entry.path), systemImage: entry.isDirectory ? "folder" : symbol)
            .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder private var fileMenu: some View {
        Button("Open in New Tab", systemImage: "plus.rectangle.on.rectangle") { Task { await workspace.open(entry.path, placement: .newTab) } }
        Button(workspace.openOnOtherSideTitle, systemImage: "rectangle.split.2x1") { Task { await workspace.open(entry.path, placement: .otherGroup) } }
        Divider()
        Button("Rename…", systemImage: "pencil") { workspace.fileSheet = .rename(entry.path) }
        Button("Move to…", systemImage: "folder") { workspace.fileSheet = .move(entry.path) }
        Button("Make a Copy", systemImage: "plus.square.on.square") { Task { await workspace.duplicate(entry.path) } }
        if let root = workspace.folderAccess?.root, let location = try? entry.path.url(in: root) {
            ShareLink(item: location) { Label("Share…", systemImage: "square.and.arrow.up") }
        }
        Button("Copy Vault Path", systemImage: "doc.on.doc") { copyToPasteboard(entry.path.rawValue) }
        Button("Copy Graphite URL", systemImage: "link") { copyToPasteboard(workspace.openingLink(to: entry.path)) }
        bookmarkButton
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { Task { await workspace.requestDeletion(of: entry.path) } }
    }

    @ViewBuilder private var folderMenu: some View {
        Button("New Note", systemImage: "doc.text") { requestCreation(.note, entry.path) }
        Button("New Notebook", systemImage: "book.closed") { requestCreation(.notebook, entry.path) }
        if workspace.preferences.isEnabled(.bases) { Button("New Base", systemImage: "tablecells") { requestCreation(.base, entry.path) } }
        Button("New Folder", systemImage: "folder.badge.plus") { workspace.fileSheet = .newFolder(in: entry.path) }
        Divider()
        Button("Rename…", systemImage: "pencil") { workspace.fileSheet = .rename(entry.path) }
        Button("Move to…", systemImage: "folder") { workspace.fileSheet = .move(entry.path) }
        Button("Make a Copy", systemImage: "plus.square.on.square") { Task { await workspace.duplicate(entry.path) } }
        Button("Copy Vault Path", systemImage: "doc.on.doc") { copyToPasteboard(entry.path.rawValue) }
        bookmarkButton
        Divider()
        Button("Delete", systemImage: "trash", role: .destructive) { Task { await workspace.requestDeletion(of: entry.path) } }
    }

    @ViewBuilder private var bookmarkButton: some View {
        if workspace.preferences.isEnabled(.bookmarks) {
            let isBookmarked = workspace.isBookmarked(entry.path)
            Button(isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: isBookmarked ? "bookmark.slash" : "bookmark") {
                Task { await workspace.toggleBookmark(entry.path) }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #endif
    }

    private var symbol: String {
        switch entry.kind {
        case .markdown: "doc.text"
        case .pdf: "doc.richtext"
        case .image: "photo"
        case .media: entry.path.fileExtension == "mp4" || entry.path.fileExtension == "mov" ? "film" : "waveform"
        case .base: "tablecells"
        case .other: "doc"
        }
    }
}

// MARK: Sheets and confirmations

/// A file sheet the sidebar or a document asks for.
enum FileSheet: Identifiable {
    case rename(VaultPath)
    case move(VaultPath)
    case newFolder(in: VaultPath)

    var id: String {
        switch self {
        case .rename(let path): "rename|" + path.rawValue
        case .move(let path): "move|" + path.rawValue
        case .newFolder(let directory): "folder|" + directory.rawValue
        }
    }
}

/// The sheets and questions of file management, attached once at the root.
struct FileManagementPresentation: ViewModifier {
    @Bindable var workspace: WorkspaceModel

    func body(content: Content) -> some View {
        content
            .sheet(item: $workspace.fileSheet) { sheet in
                Group {
                    switch sheet {
                    case .rename(let path): RenameSheet(workspace: workspace, path: path)
                    case .move(let path): MoveSheet(workspace: workspace, path: path)
                    case .newFolder(let directory): NewFolderSheet(workspace: workspace, directory: directory)
                    }
                }
                .tint(workspace.preferences.accentColor)
            }
            .confirmationDialog("Update links?", isPresented: Binding(get: { workspace.pendingMove != nil }, set: { isPresented in
                if !isPresented { workspace.pendingMove = nil }
            }), titleVisibility: .visible, presenting: workspace.pendingMove) { pendingMove in
                Button("Update Links") { Task { await workspace.resolve(pendingMove, updatesLinks: true) } }
                Button("Always Update Links") { Task { await workspace.resolve(pendingMove, updatesLinks: true, alwaysUpdates: true) } }
                Button("Don't Update") { Task { await workspace.resolve(pendingMove, updatesLinks: false) } }
                Button("Cancel", role: .cancel) {}
            } message: { pendingMove in
                let linkCount = pendingMove.plan.changedLinkCount, noteCount = pendingMove.plan.updates.count
                let change = pendingMove.path.parent == pendingMove.destination.parent
                    ? "Renaming “\(pendingMove.path.name)” to “\(pendingMove.destination.name)”"
                    : "Moving “\(pendingMove.path.name)” to “\(pendingMove.destination.parent.rawValue.isEmpty ? workspace.title : pendingMove.destination.parent.rawValue)”"
                Text("\(change) changes \(linkCount == 1 ? "1 link" : "\(linkCount) links") in \(noteCount == 1 ? "1 note" : "\(noteCount) notes"). Without the update, those links stop working.")
            }
            .confirmationDialog("Delete “\(workspace.pendingDeletion?.name ?? "")”?", isPresented: Binding(get: { workspace.pendingDeletion != nil }, set: { isPresented in
                if !isPresented { workspace.pendingDeletion = nil }
            }), titleVisibility: .visible, presenting: workspace.pendingDeletion) { path in
                Button("Delete", role: .destructive) { Task { await workspace.delete(path) } }
                Button("Cancel", role: .cancel) {}
            } message: { _ in
                switch workspace.vaultSettings.deletionMethod {
                case .systemTrash: Text("It goes to the trash, where it can be recovered.")
                case .vaultTrash: Text("It goes to the vault's .trash folder.")
                case .permanent: Text("It is deleted for good. This cannot be undone.")
                }
            }
    }
}

private struct RenameSheet: View {
    @Bindable var workspace: WorkspaceModel
    let path: VaultPath
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    /// The whole name starts selected, so typing replaces it.
    @State private var nameSelection: TextSelection?
    @FocusState private var isNameFocused: Bool

    private var isFolder: Bool { workspace.isDirectory(path) }
    private var fileExtension: String { isFolder ? "" : (path.name as NSString).pathExtension }
    private var newName: String { RenamedFileName.withoutTypedExtension(name, fileExtension: fileExtension) }
    private var problem: String? { FileNameRules.problem(with: newName, isNote: !isFolder && DocumentKind(path: path) == .markdown) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 4) {
                        TextField("Name", text: $name, selection: $nameSelection)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit(rename)
                        if !fileExtension.isEmpty { Text("." + fileExtension).foregroundStyle(.secondary) }
                    }
                } footer: {
                    if let problem, !name.isEmpty { Text(problem).foregroundStyle(.red) }
                    else if !isFolder && DocumentKind(path: path) == .markdown { Text("Links to this note are updated as the vault's settings say.") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isFolder ? "Rename Folder" : "Rename File")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Rename", action: rename).disabled(problem != nil) }
            }
        }
        .frame(minWidth: 380, minHeight: 220)
        .onAppear {
            name = originalName
            isNameFocused = true
        }
        .task {
            // The text field puts the cursor at the end when it takes focus, so the whole
            // name is selected just after that, unless typing has already begun.
            try? await Task.sleep(for: .milliseconds(350))
            guard name == originalName else { return }
            nameSelection = TextSelection(range: name.startIndex..<name.endIndex)
        }
    }

    private var originalName: String { isFolder ? path.name : path.stem }

    private func rename() {
        guard problem == nil else { return }
        let chosenName = newName
        dismiss()
        Task { await workspace.rename(path, to: chosenName) }
    }
}

/// The name a file is renamed to from what was typed.
enum RenamedFileName {
    /// Renaming keeps the file's extension, so a typed copy of it (as in a pasted
    /// "Lecture.md") is dropped rather than doubled, as the title bar's rename does.
    static func withoutTypedExtension(_ typedName: String, fileExtension: String) -> String {
        let trimmedName = typedName.trimmingCharacters(in: .whitespaces)
        guard !fileExtension.isEmpty, trimmedName.lowercased().hasSuffix("." + fileExtension.lowercased()) else { return trimmedName }
        return String(trimmedName.dropLast(fileExtension.count + 1))
    }
}

private struct NewFolderSheet: View {
    @Bindable var workspace: WorkspaceModel
    let directory: VaultPath
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @FocusState private var isNameFocused: Bool
    private var problem: String? { FileNameRules.problem(with: name, isNote: false) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Folder name", text: $name).focused($isNameFocused).submitLabel(.done).onSubmit(create)
                } footer: {
                    if let problem, !name.isEmpty { Text(problem).foregroundStyle(.red) }
                    else { Text("In “\(directory.rawValue.isEmpty ? workspace.title : directory.rawValue)”") }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Folder")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Create", action: create).disabled(problem != nil) }
            }
        }
        .frame(minWidth: 380, minHeight: 220)
        .onAppear { isNameFocused = true }
    }

    private func create() {
        guard problem == nil else { return }
        let folderName = name
        dismiss()
        Task { await workspace.createFolder(named: folderName, in: directory) }
    }
}

/// Obsidian's "Move file to…": every folder in the vault, searchable.
private struct MoveSheet: View {
    @Bindable var workspace: WorkspaceModel
    let path: VaultPath
    @Environment(\.dismiss) private var dismiss
    @State private var folders: [VaultPath] = []
    @State private var query = ""
    @State private var isLoading = true
    /// Folders listed at most; in a vault with more, the others are found by searching.
    private static let maximumListedFolderCount = 5_000

    private var matchingFolders: [VaultPath] {
        let candidates = [VaultPath.root] + folders
        let movable = candidates.filter { folder in !folder.isInside(path) && folder != path.parent }
        guard !query.isEmpty else { return Array(movable.prefix(Self.maximumListedFolderCount)) }
        return Array(movable.lazy.filter { folder in folder.rawValue.localizedCaseInsensitiveContains(query) }.prefix(Self.maximumListedFolderCount))
    }

    var body: some View {
        let listedFolders = matchingFolders
        NavigationStack {
            List(listedFolders, id: \.rawValue) { folder in
                Button {
                    dismiss()
                    Task { await workspace.move(path, into: folder) }
                } label: {
                    Label {
                        Text(folder.rawValue.isEmpty ? workspace.title : folder.rawValue).foregroundStyle(Color.primary)
                    } icon: {
                        Image(systemName: folder.rawValue.isEmpty ? "building.columns" : "folder")
                    }
                }
            }
            .overlay {
                if isLoading { ProgressView() }
                else if listedFolders.isEmpty { ContentUnavailableView.search(text: query) }
            }
            .searchable(text: $query, prompt: "Find a folder")
            .navigationTitle("Move “\(path.name)”")
            #if canImport(UIKit)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .frame(minWidth: 380, minHeight: 480)
        .task {
            guard let root = workspace.folderAccess?.root else { return }
            folders = await Task.detached(priority: .userInitiated) { Self.folders(in: root) }.value
            isLoading = false
        }
    }

    /// Every visible folder, found without reading any file.
    nonisolated private static func folders(in root: URL) -> [VaultPath] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants, .producesRelativePathURLs]) else { return [] }
        var folders: [VaultPath] = []
        while let location = enumerator.nextObject() as? URL {
            guard let values = try? location.resourceValues(forKeys: Set(keys)), values.isSymbolicLink != true else { enumerator.skipDescendants(); continue }
            if values.isDirectory == true, let folder = try? VaultPath(location.relativePath) { folders.append(folder) }
        }
        return folders.sorted { leftFolder, rightFolder in leftFolder.rawValue.localizedStandardCompare(rightFolder.rawValue) == .orderedAscending }
    }
}

extension SearchMatch {
    /// The excerpt with the matched words marked in the accent color, as search and the
    /// backlinks panel show it.
    func highlightedExcerpt(accent: Color) -> AttributedString {
        let text = NSMutableAttributedString(string: excerpt)
        let length = text.length
        for range in highlightedRanges where range.upperBound <= length {
            let highlightedRange = NSRange(location: range.lowerBound, length: range.count)
            #if canImport(UIKit)
            text.addAttribute(.foregroundColor, value: UIColor.label, range: highlightedRange)
            text.addAttribute(.backgroundColor, value: UIColor(accent).withAlphaComponent(0.22), range: highlightedRange)
            #endif
        }
        #if canImport(UIKit)
        return (try? AttributedString(text, including: \.uiKit)) ?? AttributedString(excerpt)
        #else
        return AttributedString(excerpt)
        #endif
    }
}
