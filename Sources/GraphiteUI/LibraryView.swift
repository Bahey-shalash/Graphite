/**
 * File: LibraryView.swift
 * -----------------------
 * Layer: UI
 * Description: Library mode's file browser: the folder's files and folders as a grid of pictures, as the Files app
 *              shows them, with an even number of columns over a display's fold.
 *
 * Authors: Bahey Shalash
 * Version: 0.11
 * Date: 21/10/2026
 */

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
    /// Saves a finished document scan as a new notebook in a folder; nil where the device cannot scan.
    let saveScannedNotebook: (@MainActor (ScannedDocumentPDF, Date, VaultPath?) async -> Void)?
    let reportProblem: @MainActor (String) -> Void
    /// Moves vault items into a folder, as a drop on a folder tile asks.
    let moveItems: ([VaultPath], VaultPath) -> Void
    let setSortOrder: (FileSortOrder) -> Void
    let setPresentation: (LibraryPresentation) -> Void
    /// Pictures of the vault whose name matches, for a folder's picture; recent ones for an empty query.
    let findPictures: (String) async -> [VaultPath]
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
    @Environment(\.libraryWindowActions) private var windowActions
    @State private var isDropTargeted = false
    /// How many columns the grid has over a display's fold, nil when no fold runs down it.
    @State private var columnCountOverFold: Int?

    private var tileWidth: CGFloat { horizontalSizeClass == .compact ? 110 : 140 }
    private nonisolated static let gridPaddingPoints: CGFloat = 20
    private nonisolated static let columnSpacingPoints: CGFloat = 20

    /// As many columns as tiles fit; over a fold an even number, so the fold falls between
    /// two columns rather than through a row of tiles.
    private var gridColumns: [GridItem] {
        let column = GridItem(columnCountOverFold == nil ? .adaptive(minimum: tileWidth, maximum: tileWidth * 1.3)
                                                         : .flexible(minimum: tileWidth, maximum: tileWidth * 1.3),
                              spacing: Self.columnSpacingPoints, alignment: .top)
        return Array(repeating: column, count: columnCountOverFold ?? 1)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .task(id: vault.reloadKey) {
            await library.reload(source: vault.source, sortOrder: vault.sortOrder)
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
        .font(.title3)
        .buttonStyle(.borderless)
        .padding(.leading, library.folder.rawValue.isEmpty ? 20 : 8)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
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
                .modifier(LibraryDropTarget(folder: library.folder, importFiles: actions.importFiles, isTargeted: $isDropTargeted))
        } else {
            let minimumColumnWidth = tileWidth
            ScrollView {
                LazyVGrid(columns: gridColumns, spacing: 28) {
                    ForEach(library.items) { entry in tile(for: entry) }
                }
                .padding(Self.gridPaddingPoints)
            }
            .onGeometryChange(for: Int?.self) { geometry in
                guard DisplayFoldLayout.hasFoldDownTheMiddle(DisplayFolds.activeDivisions(in: geometry), widthPoints: geometry.size.width)
                else { return nil }
                return DisplayFoldLayout.columnCount(availableWidthPoints: geometry.size.width - 2 * Self.gridPaddingPoints,
                                                     minimumColumnWidthPoints: minimumColumnWidth, spacingPoints: Self.columnSpacingPoints,
                                                     isDividedByFold: true)
            } action: { columnCount in columnCountOverFold = columnCount }
            .modifier(LibraryDropTarget(folder: library.folder, importFiles: actions.importFiles, isTargeted: $isDropTargeted))
        }
    }

    private static let unreadableFolderExplanation =
        "Graphite could not list this folder. It may have been moved, or its files may not be available on this device."

    private var emptyFolderExplanation: String {
        library.filter == .all ? "Create a notebook or a note with New." : "No file in this folder is of this kind."
    }

    private func tile(for entry: VaultEntry) -> some View {
        LibraryTile(entry: entry, library: library, entries: entries, open: { open(entry) }, moveItems: actions.moveItems,
                    findPictures: actions.findPictures)
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
    let findPictures: (String) async -> [VaultPath]
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
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    // Tag dots, as Finder and Files show them beside a name.
                    if entry.isDirectory {
                        ForEach(Array(library.folderLooks.tagColors(of: entry.path).prefix(3).enumerated()), id: \.offset) { _, tagColor in
                            Circle().fill(tagColor.tileColor).frame(width: 9, height: 9).accessibilityHidden(true)
                        }
                    }
                    Text(entries.displayName(entry.path))
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.center)
                }
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
        .modifier(LibraryTileMenu(entry: entry, library: library, entries: entries, findPictures: findPictures))
    }

    @ViewBuilder private var artwork: some View {
        if entry.isDirectory {
            LibraryFolderTileArtwork(folder: entry.path, looks: library.folderLooks, symbolPointSize: Self.artworkHeightPoints * 0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LibraryFileArtwork(entry: entry, preview: library.visiblePreviews[entry.path])
        }
    }

    private func accessibilityTitle(isBookmarked: Bool) -> String {
        let kind = entry.isDirectory ? "Folder" : entry.kind.libraryTitle
        let look = entry.isDirectory ? library.folderLooks.shownLook(of: entry.path).style.map { style in ", \(style.spokenDescription)" } ?? "" : ""
        let bookmark = isBookmarked ? ", bookmarked" : ""
        return "\(entries.displayName(entry.path)), \(kind)\(look)\(bookmark), \(entry.modified.formatted(date: .abbreviated, time: .shortened))"
    }
}

/// A tile's menu, the file tree's own, with Customize Folder… for a folder, which opens
/// Finder's folder popover over the tile (a sheet on the iPhone).
private struct LibraryTileMenu: ViewModifier {
    let entry: VaultEntry
    let library: LibraryModel
    let entries: LibraryEntryPresentation
    let findPictures: (String) async -> [VaultPath]
    @State private var isCustomizing = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if entry.isDirectory {
                    Button("Customize Folder…", systemImage: "paintpalette") { isCustomizing = true }
                    Divider()
                }
                entries.menu(entry)
            }
            .accessibilityAction(named: "Customize Folder") { if entry.isDirectory { isCustomizing = true } }
            .popover(isPresented: $isCustomizing) {
                FolderCustomizationPopover(folderName: entries.displayName(entry.path), style: library.folderLooks.shownLook(of: entry.path).style,
                                           previewImage: library.folderLooks.tileImages[entry.path], pictureActions: pictureActions) { style in
                    Task { await library.setStyle(style, for: entry.path) }
                }
                .presentationCompactAdaptation(.sheet)
                .presentationDetents([.medium, .large])
            }
    }

    private var pictureActions: FolderPictureActions {
        let library = library
        let folder = entry.path
        let looks = library.folderLooks
        return FolderPictureActions(findVaultPictures: findPictures,
                                    readVaultPicture: { path in try await library.pictureData(at: path) },
                                    applyPicture: { picture, layout, color in await library.setPicture(picture, layout: layout, color: color, for: folder) },
                                    drawPreview: { style in await looks.image(for: style) },
                                    drawFolderArt: { color in await looks.folderArt(color: color) })
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
