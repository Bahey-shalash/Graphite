import Foundation
import GraphiteCore
import GraphiteApple

/// Notebooks created from inside a note.
extension WorkspaceModel {
    /// Remembers the sheet's paper and size for the next notebook, then creates this one.
    func createNotebook(named name: String, options: NewNotebookOptions, placement: NotebookPlacement,
                        from session: MarkdownSession, request: NotebookInsertionRequest) {
        preferences.notebookCreation.remember(options)
        Task {
            await createNotebook(named: name, options: options, placement: placement, from: session,
                                 at: request.insertionRange, textWhenChosen: request.textWhenChosen)
        }
    }

    /// Creates a notebook from inside a note and puts its embed or link where the cursor was
    /// when New Notebook was chosen. Undoing the insertion removes the text and keeps the PDF.
    /// - Parameter textWhenChosen: The note's text when `range` was chosen; text typed while
    ///   the PDF is written moves the range along with it.
    func createNotebook(named name: String, options: NewNotebookOptions, placement: NotebookPlacement,
                        from session: MarkdownSession, at range: NSRange, textWhenChosen: String) async {
        guard let store, let root = folderAccess?.root else { return }
        if let problem = FileNameRules.problem(with: name, isNote: false) {
            errorMessage = problem
            return
        }
        do {
            let settings = try await store.settings()
            let directory: VaultPath
            switch placement {
            case .embeddedInNote: directory = try resolver.directory(for: settings.attachmentLocation, note: session.path)
            case .inFolder(let folder, _): directory = folder
            }
            try await store.createDirectory(directory)
            let path = try await store.uniquePath(directory: directory, stem: name, extension: "pdf")
            try await writeNotebook(options, at: path, store: store, root: root)
            let insertedText = placement.insertedText(fromEmbed: await embed(for: path, in: session.path, settings: settings))
            insertEmbed(insertedText, of: path, into: session, at: range, chosenIn: textWhenChosen)
            refreshIndex(for: [path])
            await refreshDirectory()
        } catch {
            errorMessage = "The notebook “\(name)” could not be created. Nothing was added to the note."
        }
    }
}
