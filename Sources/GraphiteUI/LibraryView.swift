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
    /// Moves vault items into a folder, as a drop on a folder tile asks.
    let moveItems: ([VaultPath], VaultPath) -> Void
    let setSortOrder: (FileSortOrder) -> Void
}

/// How each item is named and marked, and its menu: the file tree's own.
struct LibraryEntryPresentation {
    let displayName: (VaultPath) -> String
    let isBookmarked: (VaultPath) -> Bool
    let menu: (VaultEntry) -> VaultEntryMenu
}

/// The vault as the Files app shows a folder: one folder at a time, folders as the system's
/// folder symbol and files as pictures of their first page.
struct LibraryView: View {
    let library: LibraryModel
    let vault: LibraryVault
    let actions: LibraryActions
    let entries: LibraryEntryPresentation
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isDropTargeted = false

    private var tileWidth: CGFloat { horizontalSizeClass == .compact ? 110 : 140 }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .task(id: vault.reloadKey) {
            await library.reload(source: vault.source, sortOrder: vault.sortOrder)
        }
        .alert("Folder Look Not Saved", isPresented: Binding(get: { library.failure == .styleNotSaved }, set: { isShown in
            if !isShown { library.dismissFailure() }
        })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Graphite could not write the folder's color to “.obsidian/graphite-folder-styles.json”. The folder is unchanged.")
        }
    }

    // MARK: Header

    /// One quiet row, as the Files app's bar: back to the enclosing folder, the folder's name,
    /// then the view options and New as plain symbols.
    private var header: some View {
        HStack(spacing: 4) {
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
            }
            Text(title(of: library.folder))
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            viewOptionsMenu
            NewItemButton(firstKind: vault.firstCreatedKind, isEnabled: vault.isPluginEnabled, actions: newItemActions) {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("New")
        }
        .font(.title3)
        .buttonStyle(.borderless)
        .padding(.leading, library.folder.rawValue.isEmpty ? 20 : 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }

    /// What the grid shows and in which order.
    private var viewOptionsMenu: some View {
        Menu {
            Picker("Show", selection: Binding(get: { library.filter }, set: { filter in library.filter = filter })) {
                ForEach(LibraryFilter.allCases) { filter in Label(filter.title, systemImage: filter.systemImage).tag(filter) }
            }
            Picker("Sort By", selection: Binding(get: { vault.sortOrder }, set: actions.setSortOrder)) {
                ForEach(FileSortOrder.allCases) { sortOrder in Text(sortOrder.title).tag(sortOrder) }
            }
            .pickerStyle(.menu)
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
                              importFiles: { sources, directory in actions.importFiles(sources, directory ?? folder) })
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
                .modifier(LibraryDropTarget(folder: library.folder, importFiles: actions.importFiles, isTargeted: $isDropTargeted))
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: tileWidth, maximum: tileWidth * 1.3), spacing: 20, alignment: .top)], spacing: 28) {
                    ForEach(library.items) { entry in tile(for: entry) }
                }
                .padding(20)
            }
            .modifier(LibraryDropTarget(folder: library.folder, importFiles: actions.importFiles, isTargeted: $isDropTargeted))
        }
    }

    private static let unreadableFolderExplanation =
        "Graphite could not list this folder. It may have been moved, or its files may not be available on this device."

    private var emptyFolderExplanation: String {
        library.filter == .all ? "Create a notebook or a note with New." : "No file in this folder is of this kind."
    }

    private func tile(for entry: VaultEntry) -> some View {
        LibraryTile(entry: entry, library: library, entries: entries, open: { open(entry) }, moveItems: actions.moveItems)
            .onAppear { library.tileAppeared(entry) }
            .onDisappear { library.tileDisappeared(entry) }
    }

    private func open(_ entry: VaultEntry) {
        if entry.isDirectory {
            Task { await library.show(entry.path) }
        } else {
            actions.openFile(entry.path)
        }
    }
}

/// One folder or file, as the Files app's grid shows it: its picture, its name, and its date.
/// Touch and hold (or a secondary click) opens the item's menu.
private struct LibraryTile: View {
    let entry: VaultEntry
    let library: LibraryModel
    let entries: LibraryEntryPresentation
    let open: () -> Void
    let moveItems: ([VaultPath], VaultPath) -> Void
    @State private var isDropTargeted = false

    /// The picture's height; the folder symbol fills most of it.
    private static let artworkHeightPoints: CGFloat = 120

    var body: some View {
        let isBookmarked = entries.isBookmarked(entry.path)
        Button(action: open) {
            VStack(spacing: 6) {
                artwork
                    .frame(height: Self.artworkHeightPoints)
                    .padding(6)
                    .background {
                        if isDropTargeted { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.fill.secondary) }
                    }
                Text(entries.displayName(entry.path))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                HStack(spacing: 3) {
                    if isBookmarked { Image(systemName: "star.fill").imageScale(.small).accessibilityHidden(true) }
                    Text(entry.modified.formatted(date: .abbreviated, time: .omitted))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle(isBookmarked: isBookmarked))
        .accessibilityAddTraits(.isButton)
        .draggable(VaultItemTransfer(path: entry.path.rawValue))
        .modifier(FolderTileDropTarget(entry: entry, moveItems: moveItems, isTargeted: $isDropTargeted))
        .contextMenu {
            entries.menu(entry)
            if entry.isDirectory { FolderLookMenu(folder: entry.path, library: library) }
        }
    }

    @ViewBuilder private var artwork: some View {
        if entry.isDirectory {
            LibraryFolderArtwork(style: library.style(of: entry.path), symbolPointSize: Self.artworkHeightPoints * 0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LibraryFileArtwork(entry: entry, preview: library.visiblePreviews[entry.path])
        }
    }

    private func accessibilityTitle(isBookmarked: Bool) -> String {
        let kind = entry.isDirectory ? "Folder" : entry.kind.libraryTitle
        let bookmark = isBookmarked ? ", bookmarked" : ""
        return "\(entries.displayName(entry.path)), \(kind)\(bookmark), \(entry.modified.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// Folder color and symbol, in a folder's menu.
private struct FolderLookMenu: View {
    let folder: VaultPath
    let library: LibraryModel

    static let symbolNames = ["face.smiling", "compass.drawing", "moon.stars", "flask", "graduationcap", "book", "function", "gearshape",
                              "atom", "music.note", "paintpalette", "globe.europe.africa", "heart", "briefcase", "laptopcomputer", "leaf"]

    var body: some View {
        let style = library.style(of: folder)
        Menu("Folder Look", systemImage: "paintpalette") {
            Picker("Color", selection: Binding(get: { style?.color ?? .blue }, set: { color in
                apply(FolderStyle(color: color, symbolName: style?.symbolName))
            })) {
                ForEach(FolderColor.knownColors, id: \.self) { color in Text(color.title).tag(color) }
            }
            .pickerStyle(.menu)
            Picker("Symbol", selection: Binding(get: { style?.symbolName ?? "" }, set: { symbolName in
                apply(FolderStyle(color: style?.color ?? .blue, symbolName: symbolName.isEmpty ? nil : symbolName))
            })) {
                Text("None").tag("")
                ForEach(Self.symbolNames, id: \.self) { symbolName in Label(symbolName, systemImage: symbolName).labelStyle(.iconOnly).tag(symbolName) }
            }
            .pickerStyle(.menu)
            if style != nil {
                Button("Plain Folder", systemImage: "arrow.uturn.backward") { apply(nil) }
            }
        }
    }

    private func apply(_ style: FolderStyle?) {
        Task { await library.setStyle(style, for: folder) }
    }
}

/// A folder tile takes files dragged onto it.
private struct FolderTileDropTarget: ViewModifier {
    let entry: VaultEntry
    let moveItems: ([VaultPath], VaultPath) -> Void
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if entry.isDirectory {
            content.dropDestination(for: VaultItemTransfer.self) { items, _ in
                let paths = items.compactMap { item in try? VaultPath(item.path) } // A dragged name no vault path can hold moves nothing.
                    .filter { path in path != entry.path && path.parent != entry.path }
                guard !paths.isEmpty else { return false }
                moveItems(paths, entry.path)
                return true
            } isTargeted: { targeted in isTargeted = targeted }
        } else {
            content
        }
    }
}

/// The grid takes files from Files or the Finder, copied into the folder shown.
private struct LibraryDropTarget: ViewModifier {
    let folder: VaultPath
    let importFiles: ([URL], VaultPath) -> Void
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        content
            .dropDestination(for: URL.self) { sources, _ in
                let fileSources = sources.filter(\.isFileURL)
                guard !fileSources.isEmpty else { return false }
                importFiles(fileSources, folder)
                return true
            } isTargeted: { targeted in isTargeted = targeted }
            .overlay {
                if isTargeted { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2).padding(6).allowsHitTesting(false) }
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
