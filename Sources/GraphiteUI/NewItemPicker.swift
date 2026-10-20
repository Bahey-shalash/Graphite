import SwiftUI
import GraphiteCore

/// One thing the New menu creates.
enum CreatableItem: Hashable, Identifiable {
    case document(CreationKind)
    case dailyNote
    case importFiles
    case folder

    var id: Self { self }

    var title: String {
        switch self {
        case .document(.notebook): "Notebook"
        case .document(.note): "Note"
        case .document(.canvas): "Canvas"
        case .document(.base): "Base"
        case .dailyNote: "Today's Daily Note"
        case .importFiles: "Import"
        case .folder: "Folder"
        }
    }

    /// What the item makes, under its title in the large choices.
    var subtitle: String {
        switch self {
        case .document(.notebook): "PDF pages for Apple Pencil"
        case .document(.note): "Markdown text"
        case .document(.canvas): "Cards on a board"
        case .document(.base): "A table of notes"
        case .dailyNote: "Opens or creates it"
        case .importFiles: "PDFs, images and other files"
        case .folder: "In this folder"
        }
    }

    var systemImage: String {
        switch self {
        case .document(.notebook): "book.closed"
        case .document(.note): "doc.text"
        case .document(.canvas): "rectangle.3.group"
        case .document(.base): "tablecells"
        case .dailyNote: "calendar"
        case .importFiles: "square.and.arrow.down"
        case .folder: "folder.badge.plus"
        }
    }

    /// The core plugin an item needs, or nil when it is always offered.
    var requiredPlugin: CorePlugin? {
        switch self {
        case .document(.canvas): .canvas
        case .document(.base): .bases
        case .dailyNote: .dailyNotes
        case .document(.notebook), .document(.note), .importFiles, .folder: nil
        }
    }

    /// The two large choices first, in the order the person's note-taking asks for, then the
    /// rest; items whose plugin is off are left out.
    static func offered(firstKind: CreationKind, isEnabled: (CorePlugin) -> Bool) -> (large: [CreatableItem], others: [CreatableItem]) {
        let large: [CreatableItem] = firstKind == .note ? [.document(.note), .document(.notebook)] : [.document(.notebook), .document(.note)]
        let others: [CreatableItem] = [.document(.canvas), .document(.base), .dailyNote, .importFiles, .folder]
        return (large, others.filter { item in item.requiredPlugin.map(isEnabled) ?? true })
    }
}

/// The New menu, after Goodnotes': a notebook and a note as large choices, the other kinds
/// below. A popover on the iPad and the Mac, a sheet on the iPhone.
struct NewItemPicker: View {
    let firstKind: CreationKind
    let isEnabled: (CorePlugin) -> Bool
    let choose: (CreatableItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let offered = CreatableItem.offered(firstKind: firstKind, isEnabled: isEnabled)
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                ForEach(offered.large) { item in largeChoice(item) }
            }
            VStack(spacing: 0) {
                ForEach(Array(offered.others.enumerated()), id: \.element) { position, item in
                    if position > 0 { Divider().padding(.leading, 52) }
                    row(item)
                }
            }
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(16)
        .frame(idealWidth: 380)
        .presentationDetents([.medium, .large])
    }

    private func largeChoice(_ item: CreatableItem) -> some View {
        Button {
            pick(item)
        } label: {
            VStack(spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.title)
                Text(item.title)
                    .font(.headline)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, minHeight: 112)
            .padding(.horizontal, 8)
            .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func row(_ item: CreatableItem) -> some View {
        Button {
            pick(item)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: item.systemImage)
                    .frame(width: 24)
                    .foregroundStyle(.tint)
                Text(item.title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(item.subtitle)
    }

    private func pick(_ item: CreatableItem) {
        dismiss()
        choose(item)
    }
}

/// What the New menu's choices do, for one folder.
struct NewItemActions {
    /// The folder new items go to; nil for the vault's location for new files.
    let directory: VaultPath?
    let create: (CreationKind, VaultPath?) -> Void
    let openDailyNote: () -> Void
    let newFolder: (VaultPath?) -> Void
    let importFiles: ([URL], VaultPath?) -> Void
}

/// A New button that opens `NewItemPicker`, and the file chooser its Import asks for.
struct NewItemButton<Label: View>: View {
    let firstKind: CreationKind
    let isEnabled: (CorePlugin) -> Bool
    let actions: NewItemActions
    @ViewBuilder let label: () -> Label
    @State private var showsPicker = false
    @State private var showsImporter = false

    var body: some View {
        Button(action: { showsPicker = true }, label: label)
            .popover(isPresented: $showsPicker) {
                NewItemPicker(firstKind: firstKind, isEnabled: isEnabled, choose: perform)
            }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.item], allowsMultipleSelection: true) { result in
                // A cancelled chooser imports nothing; there is nothing to report.
                guard case .success(let sources) = result, !sources.isEmpty else { return }
                actions.importFiles(sources, actions.directory)
            }
    }

    private func perform(_ item: CreatableItem) {
        switch item {
        case .document(let kind): actions.create(kind, actions.directory)
        case .dailyNote: actions.openDailyNote()
        case .importFiles: showsImporter = true
        case .folder: actions.newFolder(actions.directory)
        }
    }
}
