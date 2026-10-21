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
    /// The modifier keys held at the last touch; read when the button acts (iPad with a keyboard).
    @State private var heldKeys = HeldModifierKeys()

    /// The picture's height; the folder symbol fills most of it.
    private static let artworkHeightPoints: CGFloat = 120

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
                    .frame(height: Self.artworkHeightPoints)
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
        .accessibilityLabel(accessibilityTitle(isBookmarked: isBookmarked))
        .accessibilityAddTraits(selection == .chosen ? [.isButton, .isSelected] : .isButton)
        .accessibilityHint(selection.isSelecting ? (selection == .chosen ? "Deselects it." : "Selects it.") : "")
        .modifier(ModifierKeyChoice(choose: choose, heldKeys: heldKeys))
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
    }

    private func activate() {
        // A tap with ⌘ or ⇧ held (a keyboard on the iPad) chooses, as a click does on the Mac.
        if let keyGesture = LibrarySelection.Gesture(heldKeys: heldKeys.takeKeys()) {
            choose(keyGesture)
        } else if selection.isSelecting {
            choose(Self.plainChoiceGesture)
        } else {
            open()
        }
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

/// The keyboard modifier keys held when a tile is touched, kept in a box so recording them
/// redraws nothing.
@MainActor
final class HeldModifierKeys {
    private var keys: EventModifiers = []

    func record(_ newKeys: EventModifiers) { keys = newKeys }

    /// The keys recorded at the last touch, forgotten once read, so a later activation by
    /// VoiceOver or the keyboard does not inherit them.
    func takeKeys() -> EventModifiers {
        defer { keys = [] }
        return keys
    }
}

/// ⌘-click toggles and ⇧-click extends the choice, as in the Finder. On the Mac the clicks
/// are gestures that take precedence over the button; on the iPad the keys held at the touch
/// are recorded and the button reads them, because UIKit's gestures carry no modifiers there.
private struct ModifierKeyChoice: ViewModifier {
    let choose: (LibrarySelection.Gesture) -> Void
    let heldKeys: HeldModifierKeys

    func body(content: Content) -> some View {
        #if os(macOS)
        content
            .highPriorityGesture(TapGesture().modifiers(.command).onEnded { choose(.toggle) })
            .highPriorityGesture(TapGesture().modifiers(.shift).onEnded { choose(.extendRange) })
        #else
        content.simultaneousGesture(SpatialEventGesture().onChanged { events in
            heldKeys.record(events.first?.modifierKeys ?? [])
        })
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
