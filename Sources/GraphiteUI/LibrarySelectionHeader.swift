import SwiftUI

/// What the selection bar offers for the tiles chosen.
struct LibrarySelectionBarContent {
    let chosenCount: Int
    let hasChosenAll: Bool
    /// The files to share; nil while a folder is chosen, which cannot be shared.
    let shareLocations: [URL]?
}

/// What the selection bar does.
struct LibrarySelectionBarActions {
    let toggleSelectAll: () -> Void
    let duplicate: () -> Void
    let move: () -> Void
    let delete: () -> Void
    let done: () -> Void
}

/// The library's top row while several tiles are chosen: how many, then Select All, Share,
/// Duplicate, Move, Delete and Done in the place of the view options, so it takes no row of its
/// own. A narrow window folds the four actions into one menu.
struct LibrarySelectionHeader: View {
    let content: LibrarySelectionBarContent
    let actions: LibrarySelectionBarActions
    let usesMenu: Bool

    private var title: String {
        switch content.chosenCount {
        case 0: "Select Items"
        case 1: "1 Selected"
        default: "\(content.chosenCount) Selected"
        }
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.title2.weight(.bold))
                .lineLimit(1)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            if usesMenu { actionsMenu } else { actionButtons }
            Button("Done", action: actions.done)
                .fontWeight(.semibold)
                .frame(minHeight: 44)
                .keyboardShortcut(.escape, modifiers: [])
        }
        .font(.title3)
        .buttonStyle(.borderless)
        .padding(.leading, 20)
        .padding(.trailing, 12)
        .padding(.vertical, 6)
    }

    private var selectAllTitle: String { content.hasChosenAll ? "Deselect All" : "Select All" }

    private var actionButtons: some View {
        HStack(spacing: 2) {
            Button(selectAllTitle, action: actions.toggleSelectAll)
                .font(.body)
                .keyboardShortcut("a", modifiers: .command)
                .padding(.horizontal, 8)
                .frame(minHeight: 44)
            shareControl.labelStyle(.iconOnly).frame(width: 44, height: 44)
            Button("Make a Copy", systemImage: "plus.square.on.square", action: actions.duplicate)
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
                .disabled(content.chosenCount == 0)
            Button("Move to…", systemImage: "folder", action: actions.move)
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
                .disabled(content.chosenCount == 0)
            Button("Delete", systemImage: "trash", role: .destructive, action: actions.delete)
                .labelStyle(.iconOnly).frame(width: 44, height: 44)
                .disabled(content.chosenCount == 0)
        }
    }

    private var actionsMenu: some View {
        Menu {
            Button(selectAllTitle, systemImage: "checkmark.circle", action: actions.toggleSelectAll)
                .keyboardShortcut("a", modifiers: .command)
            Divider()
            shareControl
            Button("Make a Copy", systemImage: "plus.square.on.square", action: actions.duplicate).disabled(content.chosenCount == 0)
            Button("Move to…", systemImage: "folder", action: actions.move).disabled(content.chosenCount == 0)
            Button("Delete", systemImage: "trash", role: .destructive, action: actions.delete).disabled(content.chosenCount == 0)
        } label: {
            Image(systemName: "ellipsis.circle").frame(width: 44, height: 44).contentShape(Rectangle())
        }
        .accessibilityLabel("Actions for the Selection")
    }

    /// Share needs files: with a folder chosen it says why it is off.
    @ViewBuilder private var shareControl: some View {
        if let shareLocations = content.shareLocations, !shareLocations.isEmpty {
            ShareLink(items: shareLocations) { Label("Share…", systemImage: "square.and.arrow.up") }
        } else {
            Button("Share…", systemImage: "square.and.arrow.up") {}
                .disabled(true)
                .help(content.chosenCount == 0 ? "Choose files to share" : "Folders cannot be shared; choose files only")
        }
    }
}
