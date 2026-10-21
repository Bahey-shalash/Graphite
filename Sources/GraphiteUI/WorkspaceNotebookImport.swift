import Foundation
import GraphiteCore
import GraphiteApple
import NotebookImport

/// Importing Goodnotes and Notability notebooks: the New menu's Import, the library's, and files dropped on the library
/// or the file list all reach `importFiles(from:into:)`, which hands the notebooks and folders to this. The share
/// sheet will too, once the share extension delivers its files into the vault through the same call.
extension WorkspaceModel {
    /// The sources an import converts as notebooks while the Notebook Import core plugin is on: Goodnotes and Notability
    /// files, and folders, such as a library export, whose notebooks are converted and whose folders are kept. Read from
    /// the locations only; nothing is opened.
    func notebookImportSources(in sources: [URL]) -> [URL] {
        guard preferences.isEnabled(.notebookImport) else { return [] }
        return sources.filter { source in source.hasDirectoryPath || NotebookFileFormat(fileExtension: source.pathExtension) != nil }
    }

    /// Converts the notebooks of `sources` into `directory`, away from the main actor, while the vault stays usable; the
    /// progress shows over the document area and a report follows (`NotebookImportPresentation`). One import runs at a
    /// time: while one runs, the person is told to wait.
    func importNotebooks(_ sources: [URL], into directory: VaultPath) {
        guard let store, let root = folderAccess?.root else { return }
        guard notebookImport == nil else {
            errorMessage = "Notebooks are already being imported. Import these when that import has finished."
            return
        }
        // The one read of the wall clock for an import: every imported stroke is dated when the import began.
        let run = NotebookImportRun(vault: notebookImportVault(store: store, root: root), conversion: NotebookConversion(fileWriter: store.writer),
                                    limits: .standard, strokeCreationDate: .now)
        notebookImport = NotebookImportSession(sources: sources, destination: directory, run: run)
    }

    /// Lets the import go once its report is closed, so nothing of it stays.
    func endNotebookImport() {
        notebookImport?.stopImportAndObservation()
        notebookImport = nil
    }

    private func notebookImportVault(store: VaultStore, root: URL) -> NotebookImportVault {
        NotebookImportVault(freePath: { folder, stem, fileExtension in try await store.uniquePath(directory: folder, stem: stem, extension: fileExtension) },
                            makeFolder: { folder in try await store.createDirectory(folder) },
                            location: { path in try path.url(in: root) },
                            fileWriter: store.writer,
                            filesDidChange: { [weak self] paths in
                                self?.refreshIndex(for: paths)
                                await self?.refreshDirectory()
                            })
    }
}
