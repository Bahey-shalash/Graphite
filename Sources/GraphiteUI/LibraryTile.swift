import SwiftUI
import GraphiteCore
import GraphiteApple

/// Whether a tile is being chosen along with others, and if so whether it is chosen.
enum LibraryTileSelection: Equatable {
    case notSelecting
    case unchosen
    case chosen

    var isSelecting: Bool { self != .notSelecting }
}

/// One folder or file, as the Files app's grid shows it: its picture, its name, and its date.
/// Touch and hold (or a secondary click) opens the item's menu. While several tiles are
/// being chosen, a tap chooses the tile instead of opening it.
struct LibraryTile: View {
    let entry: VaultEntry
    let library: LibraryModel
    let entries: LibraryEntryPresentation
    let selection: LibraryTileSelection
    let open: () -> Void
    /// A click or tap that chooses the tile; a plain one acts as the platform's plain click does.
    let choose: (LibrarySelection.Gesture) -> Void
    let dropActions: LibraryDropActions
    let findPictures: (String) async -> [VaultPath]
    @State private var isDropTargeted = false

    @ScaledMetric(relativeTo: .subheadline) private var textScale: CGFloat = 1
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The picture's height at the default text size; the folder symbol fills most of it.
    static let baseArtworkHeightPoints: CGFloat = 120
    /// Larger text makes the tile larger with it, up to this factor, so a column still fits the screen.
    static let maximumTextScale: CGFloat = 2

    private var artworkHeightPoints: CGFloat { Self.baseArtworkHeightPoints * min(textScale, Self.maximumTextScale) }

    /// A plain click on the Mac chooses the tile alone, as in the Finder; a tap toggles it.
    private static var plainChoiceGesture: LibrarySelection.Gesture {
        #if os(macOS)
        .replace
        #else
        .toggle
        #endif
    }

    var body: some View {
        let isBookmarked = entries.isBookmarked(entry.path)
        Button(action: activate) {
            VStack(spacing: 6) {
                artwork
                    .frame(height: artworkHeightPoints)
                    .padding(6)
                    .background {
                        if isDropTargeted { RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.fill.secondary) }
                    }
                    .overlay(alignment: .bottomTrailing) { selectionMark }
                caption(isBookmarked: isBookmarked)
            }
            .padding(4)
            .background {
                if selection == .chosen { RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.accentColor.opacity(0.18)) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        // The favorite state is spoken once, as the value; the star beside the date is decoration.
        .accessibilityValue(isBookmarked ? "Bookmarked" : "")
        .accessibilityAddTraits(selection == .chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selection.isSelecting ? (selection == .chosen ? "Deselects it." : "Selects it.") : "")
        .accessibilityActions {
            // The context menu's actions, which VoiceOver offers as custom actions too.
            if !selection.isSelecting {
                ForEach(entries.accessibilityActions(entry)) { entryAction in Button(entryAction.title, action: entryAction.perform) }
            }
        }
        .modifier(ModifierKeyChoice(choose: choose))
        #if os(macOS)
        // While choosing, a plain click only chooses; a double-click opens, as in the Finder.
        .simultaneousGesture(TapGesture(count: 2).onEnded { if selection.isSelecting { open() } })
        #endif
        .draggable(containerItemID: entry.path.rawValue)
        .modifier(FolderTileDropTarget(entry: entry, actions: dropActions, isTargeted: $isDropTargeted))
        .modifier(LibraryTileMenu(entry: entry, library: library, entries: entries, isMenuAvailable: !selection.isSelecting, findPictures: findPictures))
    }

    /// The name with a folder's tag dots, then the date and the bookmark star.
    private func caption(isBookmarked: Bool) -> some View {
        VStack(spacing: 6) {
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? Self.accessibilityNameLineLimit : 2)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 3) {
                if isBookmarked { Image(systemName: "star.fill").imageScale(.small).accessibilityHidden(true) }
                Text(subtitle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// Names wrap to this many lines at accessibility text sizes, so a long name is read in full.
    private static let accessibilityNameLineLimit = 6

    /// A folder says how many items it holds, as the Files app does; a file says when it changed.
    private var subtitle: String {
        if entry.isDirectory, let itemCount = library.folderItemCounts.counts[entry.path] { return LibraryTileSpokenLabel.itemCountText(itemCount) }
        return entry.modified.formatted(date: .abbreviated, time: .omitted)
    }

    private func activate() {
        if selection.isSelecting { choose(Self.plainChoiceGesture) } else { open() }
    }

    /// The empty circle of a tile that can be chosen, and the checked one of a chosen tile.
    @ViewBuilder private var selectionMark: some View {
        if selection.isSelecting {
            Image(systemName: selection == .chosen ? "checkmark.circle.fill" : "circle")
                .font(.title3)
                .symbolRenderingMode(selection == .chosen ? .palette : .monochrome)
                .foregroundStyle(selection == .chosen ? Color.white : Color.secondary, Color.accentColor)
                .background { if selection != .chosen { Circle().fill(.background.opacity(0.7)) } }
                .padding(4)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var artwork: some View {
        if entry.isDirectory {
            LibraryFolderTileArtwork(folder: entry.path, looks: library.folderLooks, symbolPointSize: artworkHeightPoints * 0.8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            LibraryFileArtwork(entry: entry, preview: library.visiblePreviews[entry.path])
        }
    }

    /// A file as name, kind and date; a folder as name, look and item count.
    private var accessibilityTitle: String {
        let name = entries.displayName(entry.path)
        guard entry.isDirectory else {
            let modifiedText = entry.modified.formatted(date: .abbreviated, time: .shortened)
            return LibraryTileSpokenLabel.file(name: name, kind: entry.kind.libraryTitle, modifiedText: modifiedText)
        }
        return LibraryTileSpokenLabel.folder(name: name, lookDescription: library.folderLooks.shownLook(of: entry.path).style?.spokenDescription,
                                             itemCount: library.folderItemCounts.counts[entry.path])
    }
}

/// ⌘-click toggles and ⇧-click extends the choice, as in the Finder. They are gestures that take
/// precedence over the button, which a plain click still reaches. On the iPad a tap only chooses
/// or opens: a gesture reading the keys held at the touch stopped the grid from scrolling.
private struct ModifierKeyChoice: ViewModifier {
    let choose: (LibrarySelection.Gesture) -> Void

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .highPriorityGesture(TapGesture().modifiers(.command).onEnded { choose(.toggle) })
            .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { choose(.extendRange) })
        #else
        content
        #endif
    }
}

/// A tile's menu, the file tree's own, with Customize Folder… for a folder, which opens
/// Finder's folder popover over the tile (a sheet on the iPhone). While several tiles are
/// being chosen the selection bar holds the actions and the tile has no menu.
private struct LibraryTileMenu: ViewModifier {
    let entry: VaultEntry
    let library: LibraryModel
    let entries: LibraryEntryPresentation
    let isMenuAvailable: Bool
    let findPictures: (String) async -> [VaultPath]
    @State private var isCustomizing = false

    func body(content: Content) -> some View {
        content
            .contextMenu {
                if isMenuAvailable {
                    if entry.isDirectory {
                        Button("Customize Folder…", systemImage: "paintpalette") { isCustomizing = true }
                        Divider()
                    }
                    entries.menu(entry)
                }
            }
            .accessibilityAction(named: "Customize Folder") { if entry.isDirectory && isMenuAvailable { isCustomizing = true } }
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

/// A folder tile takes items dragged onto it: vault items move into the folder, and files from
/// other apps are copied into it. A file tile takes nothing.
private struct FolderTileDropTarget: ViewModifier {
    let entry: VaultEntry
    let actions: LibraryDropActions
    @Binding var isTargeted: Bool

    func body(content: Content) -> some View {
        if entry.isDirectory {
            content.modifier(LibraryDropDestination(folder: entry.path, actions: actions, isTargeted: $isTargeted))
        } else {
            content
        }
    }
}
