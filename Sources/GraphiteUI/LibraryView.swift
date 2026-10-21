import SwiftUI
import GraphiteCore
import GraphiteApple

/// What the library shows of the open vault, as values its caller reads from the workspace.
struct LibraryVault {
    let source: LibraryModel.Source?
    /// The vault's name, the root folder's title.
    let title: String
    let sortOrder: FileSortOrder
    /// Changes whenever Graphite or another app may have changed the vault's files.
    let listingVersion: Int
    let firstCreatedKind: CreationKind
    let isPluginEnabled: (CorePlugin) -> Bool
    let presentation: LibraryPresentation
    /// The vault's "Confirm file deletion" and "Deleted files" settings, which deleting the selection follows.
    let confirmsDeletion: Bool
    let deletionMethod: DeletionMethod

    /// Lists again when the vault, its sort order, or its files change.
    var reloadKey: String {
        "\(source?.vaultIdentifier.uuidString ?? "")|\(listingVersion)|\(sortOrder.rawValue)"
    }
}

/// What the library asks the workspace to do.
struct LibraryActions {
    /// Opens a chosen file; the caller decides where.
    let openFile: (VaultPath) -> Void
    let requestCreation: (CreationKind, VaultPath?) -> Void
    let openDailyNote: () -> Void
    let newFolder: (VaultPath) -> Void
    let importFiles: ([URL], VaultPath) -> Void
    /// Takes what a drop carries for a folder; see `LibraryDropActions.receive`.
    let receiveDrop: ([NSItemProvider], VaultPath) -> Bool
    /// Saves a finished document scan as a new notebook in a folder; nil where the device cannot scan.
    let saveScannedNotebook: (@MainActor (ScannedDocumentPDF, Date, VaultPath?) async -> Void)?
    let reportProblem: @MainActor (String) -> Void
    /// Moves vault items into a folder, as a drop on a folder tile asks.
    let moveItems: ([VaultPath], VaultPath) -> Void
    let setSortOrder: (FileSortOrder) -> Void
    let setPresentation: (LibraryPresentation) -> Void
    /// Pictures of the vault whose name matches, for a folder's picture; recent ones for an empty query.
    let findPictures: (String) async -> [VaultPath]
    /// Deletes the items one by one, as the file tree does; the question was asked already.
    let deleteItems: ([VaultPath]) -> Void
    /// Makes a copy of each item beside it.
    let duplicateItems: ([VaultPath]) -> Void
    /// Asks which folder the items move to.
    let requestMove: ([VaultPath]) -> Void
}

/// How each item is named and marked, and its menu: the file tree's own.
struct LibraryEntryPresentation {
    let displayName: (VaultPath) -> String
    let isBookmarked: (VaultPath) -> Bool
    let menu: (VaultEntry) -> VaultEntryMenu
    /// The menu's actions as VoiceOver's custom actions.
    let accessibilityActions: (VaultEntry) -> [LibraryEntryAction]
    /// Where a file is on disk, for sharing; nil outside the vault.
    let fileLocation: (VaultPath) -> URL?
}

/// One action of an item's menu, as VoiceOver offers it.
struct LibraryEntryAction: Identifiable {
    let action: VaultEntryAction
    let title: String
    let perform: () -> Void

    var id: VaultEntryAction { action }
}

/// The vault as the Files app shows a folder: one folder at a time, folders as the system's
/// folder symbol and files as pictures of their first page.
struct LibraryView: View {
    let library: LibraryModel
    let vault: LibraryVault
    let actions: LibraryActions
    let entries: LibraryEntryPresentation
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.libraryWindowActions) private var windowActions
    @State private var isDropTargeted = false
    @State private var selection = LibrarySelection()
    @State private var isConfirmingDeletion = false
    @State private var isBackTargeted = false

    @ScaledMetric(relativeTo: .subheadline) private var textScale: CGFloat = 1

    /// Larger text widens the tiles with it, so names keep their line length and a column still fits.
    private var tileWidth: CGFloat { (horizontalSizeClass == .compact ? 110 : 140) * min(textScale, LibraryTile.maximumTextScale) }

    var body: some View {
        VStack(spacing: 0) {
            if selection.isSelecting { selectionHeader } else { header }
            content
        }
        .task(id: vault.reloadKey) {
            await library.reload(source: vault.source, sortOrder: vault.sortOrder)
        }
        .onChange(of: library.items) { keepChosenTilesListed() }
        .onChange(of: library.folder) { selection.end() }
        .confirmationDialog("Delete \(selection.chosenCount) \(selection.chosenCount == 1 ? "Item" : "Items")?",
                            isPresented: $isConfirmingDeletion, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { actions.deleteItems(chosenPaths) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(vault.deletionMethod.confirmationExplanation(itemCount: selection.chosenCount))
        }
        .alert(noticeTitle, isPresented: Binding(get: { noticeMessage != nil }, set: { isShown in
            if !isShown { library.dismissFailure() }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(noticeMessage ?? "")
        }
    }

    private var noticeTitle: String {
        switch library.failure {
        case .styleNotSaved: "Folder Look Not Saved"
        case .finderLookNotWritten: "Finder Not Updated"
        case .folderStylesSetAside, .folderStylesUnreadable, .folderUnreadable, nil: "Folder Colors Reset"
        }
    }

    /// What the library tells the person once; a folder it cannot list is shown in place instead.
    private var noticeMessage: String? {
        switch library.failure {
        case .styleNotSaved:
            "Graphite could not write the folder's color to “.obsidian/graphite-folder-styles.json”. The folder is unchanged."
        case .finderLookNotWritten:
            "The folder's look is saved for Graphite, but Finder could not be given it, so Finder still shows the folder as before."
        case .folderStylesSetAside(let keptCopyName):
            "“.obsidian/graphite-folder-styles.json” was not in a form Graphite can read, so it was kept as “\(keptCopyName)” and the folders show plain."
        case .folderStylesUnreadable:
            "“.obsidian/graphite-folder-styles.json” is not in a form Graphite can read, so the folders show plain. The file is left as it is."
        case .folderUnreadable, nil:
            nil
        }
    }

    // MARK: Header

    /// One quiet row, as the Files app's bar: back to the enclosing folder, the folder's name,
    /// then the view options and New as plain symbols.
    private var header: some View {
        // The title and the controls share a row while they fit; at large text sizes the title takes a row of its own.
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                backButton
                headerTitle(lineLimit: 1).fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                headerControls
            }
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    backButton
                    headerTitle(lineLimit: 3)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 4) {
                    Spacer(minLength: 0)
                    headerControls
                }
            }
        }
        .font(.title3)
        .buttonStyle(.borderless)
        .padding(.leading, library.folder.rawValue.isEmpty ? 20 : 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }

    private func headerTitle(lineLimit: Int) -> some View {
        Text(title(of: library.folder))
            .font(.title2.weight(.bold))
            .lineLimit(lineLimit)
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var backButton: some View {
            if !library.folder.rawValue.isEmpty {
                Button {
                    Task { await library.show(library.folder.parent) }
                } label: {
                    Label(title(of: library.folder.parent), systemImage: "chevron.backward")
                        .labelStyle(.iconOnly)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .font(.title3.weight(.medium))
                .accessibilityLabel("Back to \(title(of: library.folder.parent))")
                // Dropping on it moves into the enclosing folder, the way up a level.
                .background { if isBackTargeted { Circle().fill(.fill.secondary) } }
                .modifier(LibraryDropDestination(folder: library.folder.parent, actions: dropActions, isTargeted: $isBackTargeted))
            }
    }

    /// The symbols keep a size a finger can hit; only the title and the tiles follow the text size beyond that.
    @ViewBuilder private var headerControls: some View {
        headerControlButtons.dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    @ViewBuilder private var headerControlButtons: some View {
            windowButtons
            LibraryPresentationSwitch(presentation: vault.presentation, choose: actions.setPresentation)
                .padding(.horizontal, 4)
            viewOptionsMenu
            NewItemButton(firstKind: vault.firstCreatedKind, isEnabled: vault.isPluginEnabled, actions: newItemActions) {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("New")
    }

    /// Settings and the quick switcher, which the sidebar offered before the library
    /// replaced it; a phone's sidebar still has them.
    @ViewBuilder private var windowButtons: some View {
        if let windowActions, horizontalSizeClass != .compact {
            Button("Settings", systemImage: "gearshape", action: windowActions.showSettings)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .help("Settings")
            Button("Find a File", systemImage: "magnifyingglass", action: windowActions.showSearch)
                .labelStyle(.iconOnly)
                .frame(width: 44, height: 44)
                .help("Find a file (⌘O)")
        }
    }

    /// What the grid shows and in which order.
    private var viewOptionsMenu: some View {
        Menu {
            Button("Select", systemImage: "checkmark.circle") { selection.begin() }
                .disabled(library.items.isEmpty)
            Divider()
            Picker("Show", selection: Binding(get: { library.filter }, set: { filter in library.filter = filter })) {
                ForEach(LibraryFilter.allCases) { filter in Label(filter.title, systemImage: filter.systemImage).tag(filter) }
            }
            Picker("Sort By", selection: Binding(get: { vault.sortOrder }, set: actions.setSortOrder)) {
                ForEach(FileSortOrder.allCases) { sortOrder in Text(sortOrder.title).tag(sortOrder) }
            }
            .pickerStyle(.menu)
            // The sidebar held these; in Library mode there is none.
            if let windowActions, horizontalSizeClass != .compact {
                Divider()
                Button("Vaults…", systemImage: "books.vertical", action: windowActions.showVaults)
            }
        } label: {
            Image(systemName: library.filter == .all ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("View Options")
    }

    private func title(of folder: VaultPath) -> String {
        folder.rawValue.isEmpty ? vault.title : folder.name
    }

    private var newItemActions: NewItemActions {
        let folder = library.folder
        return NewItemActions(directory: folder,
                              create: actions.requestCreation,
                              openDailyNote: actions.openDailyNote,
                              newFolder: { directory in actions.newFolder(directory ?? folder) },
                              importFiles: { sources, directory in actions.importFiles(sources, directory ?? folder) },
                              saveScannedNotebook: actions.saveScannedNotebook,
                              reportProblem: actions.reportProblem)
    }

    // MARK: Grid

    @ViewBuilder private var content: some View {
        if library.failure == .folderUnreadable {
            ContentUnavailableView("Can't Show This Folder", systemImage: "exclamationmark.triangle",
                                   description: Text(Self.unreadableFolderExplanation))
        } else if library.items.isEmpty {
            ContentUnavailableView(library.filter == .all ? "Nothing Here Yet" : "Nothing to Show",
                                   systemImage: "square.grid.2x2",
                                   description: Text(emptyFolderExplanation))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .modifier(LibraryDropDestination(folder: library.folder, actions: dropActions, isTargeted: $isDropTargeted))
                .modifier(LibraryDropRing(isTargeted: isDropTargeted))
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth * 1.3), spacing: 20, alignment: .top)], spacing: 28) {
                    ForEach(library.items) { entry in tile(for: entry) }
                }
                .padding(20)
            }
            // A drag that starts on a chosen tile carries every chosen tile.
            .dragContainer(for: VaultItemTransfer.self, itemID: \.path) { draggedPaths in draggedPaths.map(draggedItem(forRawPath:)) }
            .dragContainerSelection(selection.chosenPaths.map(\.rawValue))
            .modifier(LibraryDropDestination(folder: library.folder, actions: dropActions, isTargeted: $isDropTargeted))
            .modifier(LibraryDropRing(isTargeted: isDropTargeted))
        }
    }

    private static let unreadableFolderExplanation =
        "Graphite could not list this folder. It may have been moved, or its files may not be available on this device."

    private var emptyFolderExplanation: String {
        library.filter == .all ? "Create a notebook or a note with New." : "No file in this folder is of this kind."
    }

    private func tile(for entry: VaultEntry) -> some View {
        LibraryTile(entry: entry, library: library, entries: entries, selection: tileSelection(of: entry), open: { open(entry) },
                    choose: { gesture in choose(entry, with: gesture) }, dropActions: dropActions, findPictures: actions.findPictures)
            .onAppear { library.tileAppeared(entry) }
            .onDisappear { library.tileDisappeared(entry) }
    }

    private var dropActions: LibraryDropActions {
        LibraryDropActions(receive: actions.receiveDrop)
    }

    /// A dragged item as other apps take it too: its path for Graphite, its file for the rest.
    private func draggedItem(forRawPath rawPath: String) -> VaultItemTransfer {
        let location = (try? VaultPath(rawPath)).flatMap(entries.fileLocation) // A name no vault path can hold has no file to give.
        return VaultItemTransfer(path: rawPath, fileLocation: location)
    }

    private func open(_ entry: VaultEntry) {
        if entry.isDirectory {
            Task { await library.show(entry.path) }
        } else {
            actions.openFile(entry.path)
        }
    }
}

extension LibraryFilter {
    var title: String {
        switch self {
        case .all: "All"
        case .notebooks: "Notebooks and PDFs"
        case .notes: "Notes"
        case .pictures: "Pictures and Drawings"
        case .boards: "Canvases and Bases"
        }
    }

    var systemImage: String {
        switch self {
        case .all: "square.grid.2x2"
        case .notebooks: "book.closed"
        case .notes: "doc.text"
        case .pictures: "photo"
        case .boards: "rectangle.3.group"
        }
    }
}

extension DocumentKind {
    var libraryTitle: String {
        switch self {
        case .markdown: "Note"
        case .pdf: "PDF"
        case .image: "Picture"
        case .media: "Recording"
        case .base: "Base"
        case .canvas: "Canvas"
        case .other: "File"
        }
    }
}

/// Library or List, side by side as two symbols with the one shown selected, as Files and
/// the Finder switch between icons and a list.
struct LibraryPresentationSwitch: View {
    let presentation: LibraryPresentation
    let choose: (LibraryPresentation) -> Void

    var body: some View {
        Picker("Show Files As", selection: Binding(get: { presentation }, set: choose)) {
            ForEach(LibraryPresentation.allCases) { presentation in
                Label(presentation.title, systemImage: presentation.systemImage).tag(presentation)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .fixedSize()
        .help("Show files as a library or as a list")
    }
}

// MARK: Choosing several tiles

extension LibraryView {
    func tileSelection(of entry: VaultEntry) -> LibraryTileSelection {
        guard selection.isSelecting else { return .notSelecting }
        return selection.isChosen(entry.path) ? .chosen : .unchosen
    }

    /// A click or tap that chooses a tile; outside selection, a ⌘-click or ⇧-click starts it, as the Finder does.
    func choose(_ entry: VaultEntry, with gesture: LibrarySelection.Gesture) {
        if !selection.isSelecting { selection.begin() }
        selection.apply(gesture, to: entry.path, among: library.items.map(\.path))
    }

    /// The chosen tiles in the order shown.
    var chosenPaths: [VaultPath] { selection.chosenPaths(in: library.items.map(\.path)) }

    /// After the folder is listed again: tiles that are gone (moved, deleted, renamed) leave the
    /// choice, and choosing ends once everything chosen has gone.
    func keepChosenTilesListed() {
        guard selection.isSelecting, selection.chosenCount > 0 else { return }
        selection.keepListed(library.items.map(\.path))
        if selection.chosenCount == 0 { selection.end() }
    }

    var selectionHeader: some View {
        let chosenEntries = library.items.filter { entry in selection.isChosen(entry.path) }
        let shareLocations: [URL]? = chosenEntries.contains(where: \.isDirectory) ? nil : chosenEntries.compactMap { entry in entries.fileLocation(entry.path) }
        return LibrarySelectionHeader(
            content: LibrarySelectionBarContent(chosenCount: selection.chosenCount,
                                                hasChosenAll: selection.hasChosenAll(listedCount: library.items.count),
                                                shareLocations: shareLocations),
            actions: LibrarySelectionBarActions(
                toggleSelectAll: { toggleSelectAll() },
                duplicate: {
                    actions.duplicateItems(chosenPaths)
                    selection.end()
                },
                move: { actions.requestMove(chosenPaths) },
                delete: { requestDeletionOfChosenTiles() },
                done: { selection.end() }),
            usesMenu: horizontalSizeClass == .compact)
    }

    private func toggleSelectAll() {
        if selection.hasChosenAll(listedCount: library.items.count) {
            selection.deselectAll()
        } else {
            selection.selectAll(of: library.items.map(\.path))
        }
    }

    private func requestDeletionOfChosenTiles() {
        if vault.confirmsDeletion { isConfirmingDeletion = true } else { actions.deleteItems(chosenPaths) }
    }
}
