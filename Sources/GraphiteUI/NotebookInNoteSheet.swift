import SwiftUI
import GraphiteCore
import GraphiteApple

/// A request to create a notebook from inside a note, with where the cursor was.
struct NotebookInsertionRequest: Identifiable {
    let id = UUID()
    let insertionRange: NSRange
    /// The note's text when New Notebook was chosen, for placing the embed or link.
    let textWhenChosen: String

    @MainActor init(session: MarkdownSession) {
        // After a selection rather than over it, as a new drawing goes: the text is
        // inserted only once the sheet closes, where a deletion would go unseen.
        insertionRange = NSRange(location: NSMaxRange(session.selection), length: 0)
        textWhenChosen = session.text
    }
}

/// The New Notebook sheet with the choice of where the notebook lives: embedded in the
/// note, or as its own file in a folder with a link or embed in the note.
struct NotebookInNoteSheet: View {
    let notePath: VaultPath
    /// Where the note's attachments go, as the sheet describes it.
    let attachmentFolderDescription: String
    let initialOptions: NewNotebookOptions
    let create: (String, NewNotebookOptions, NotebookPlacement) -> Void

    private enum Location: Hashable { case embedded, folder }

    @State private var location = Location.embedded
    @State private var folder: VaultPath
    @State private var insertsEmbed = false

    init(notePath: VaultPath, attachmentFolderDescription: String, initialOptions: NewNotebookOptions,
         create: @escaping (String, NewNotebookOptions, NotebookPlacement) -> Void) {
        self.notePath = notePath
        self.attachmentFolderDescription = attachmentFolderDescription
        self.initialOptions = initialOptions
        self.create = create
        _folder = State(initialValue: notePath.parent)
    }

    var body: some View {
        NewNotebookSheet(folderDescription: folderDescription, initialOptions: initialOptions) {
            placementControls
        } create: { name, options in
            create(name, options, placement)
        }
    }

    private var placement: NotebookPlacement {
        switch location {
        case .embedded: .embeddedInNote
        case .folder: .inFolder(folder, insertsEmbed: insertsEmbed)
        }
    }

    private var folderDescription: String {
        switch location {
        case .embedded: attachmentFolderDescription
        case .folder: Self.title(of: folder)
        }
    }

    private var placementControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Where", selection: $location) {
                Text("Embedded in This Note").tag(Location.embedded)
                Text("In a Folder").tag(Location.folder)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text(locationExplanation)
                .font(.footnote)
                .foregroundStyle(.secondary)
            if location == .folder {
                NotebookSettingsCard {
                    Picker("Folder", selection: $folder) {
                        ForEach(folderChoices, id: \.self) { choice in Text(Self.title(of: choice)).tag(choice) }
                    }
                    .padding(.vertical, 6)
                    Divider()
                    Picker("In the Note", selection: $insertsEmbed) {
                        Text("Link").tag(false)
                        Text("Embed").tag(true)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var locationExplanation: String {
        switch location {
        case .embedded: "Written on inside the note, like a drawing, and saved with the note's attachments."
        case .folder: "Its own notebook in the library, with a link to it in the note."
        }
    }

    /// The note's folder and every folder above it, up to the vault.
    private var folderChoices: [VaultPath] {
        var choices = [notePath.parent]
        while let last = choices.last, !last.rawValue.isEmpty { choices.append(last.parent) }
        return choices
    }

    private static func title(of folder: VaultPath) -> String {
        folder.rawValue.isEmpty ? "Vault folder" : folder.rawValue
    }
}

/// Shows the New Notebook sheet a note's tab asked for, and creates the notebook.
struct NotebookInsertionPresentation: ViewModifier {
    @Bindable var document: TabDocument
    let notePath: VaultPath
    /// Where the note's attachments go, as the sheet describes it.
    let attachmentFolderDescription: String
    let initialOptions: () -> NewNotebookOptions
    let create: (String, NewNotebookOptions, NotebookPlacement, NotebookInsertionRequest) -> Void

    func body(content: Content) -> some View {
        content.sheet(item: $document.notebookInsertion) { request in
            NotebookInNoteSheet(notePath: notePath, attachmentFolderDescription: attachmentFolderDescription,
                                initialOptions: initialOptions()) { name, options, placement in
                create(name, options, placement, request)
            }
        }
    }
}
