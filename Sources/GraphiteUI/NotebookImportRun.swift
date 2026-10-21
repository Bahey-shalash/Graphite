import Foundation
import GraphiteCore
import GraphiteApple
import NotebookImport

/// The work of one notebook import, away from the main actor: lists the chosen folders, then converts the notebooks
/// one at a time, each into a PDF and its recordings in the vault, never changing a source. A chosen folder becomes a
/// new folder of its name (a free one, "Courses 1" when "Courses" is taken) holding the same subfolders as the source,
/// and a chosen notebook goes into the destination folder itself. Each file takes a free name. Cancelling stops at the
/// next page: the notebook being converted leaves nothing, the ones before stay, the rest are not started.
struct NotebookImportRun: Sendable {
    /// The name of an imported notebook whose file name leaves nothing usable, such as ".goodnotes".
    static let fallbackNotebookName = "Imported Notebook"
    /// What separates the notebook's name from its recording's in a recording's file name: "Lecture 3 - Recording 1.m4a".
    static let recordingNameSeparator = " - "

    let vault: NotebookImportVault
    let conversion: NotebookConversion
    let limits: NotebookImportLimits
    /// The creation date of every imported stroke: when the import began.
    let strokeCreationDate: Date

    /// A notebook to convert and the vault folder it goes into.
    private struct Item {
        let location: URL
        let format: NotebookFileFormat
        let folder: VaultPath
    }

    func run(sources: [URL], into destination: VaultPath, progress: AsyncStream<NotebookImportProgress>.Continuation) async -> NotebookImportSummary {
        var summary = NotebookImportSummary()
        let accessedSources = sources.filter { source in source.startAccessingSecurityScopedResource() }
        defer { for source in accessedSources { source.stopAccessingSecurityScopedResource() } }
        progress.yield(.listing)
        let items = await items(for: sources, into: destination, summary: &summary)
        var state = NotebookImportProgress(notebookCount: items.count, finishedNotebookCount: 0, currentNotebookName: nil, currentPageCount: 0,
                                           finishedPageCount: 0)
        progress.yield(state)
        for item in items {
            let name = item.location.lastPathComponent
            guard !Task.isCancelled else {
                summary.outcomes.append(NotebookImportOutcome(id: item.location, sourceName: name, result: .notStarted))
                continue
            }
            state.currentNotebookName = name
            state.currentPageCount = 0
            state.finishedPageCount = 0
            progress.yield(state)
            let result = await convert(item, progress: progress, state: state)
            if case .notStarted = result { summary.wasCancelled = true }
            summary.outcomes.append(NotebookImportOutcome(id: item.location, sourceName: name, result: result))
            state.finishedNotebookCount += 1
        }
        summary.wasCancelled = summary.wasCancelled || Task.isCancelled
        return summary
    }

    /// The notebooks of the sources, in the order chosen: a notebook as it is, a folder's notebooks in Finder's order. A
    /// folder's own vault folder is made here, so its name is held before any notebook is written.
    private func items(for sources: [URL], into destination: VaultPath, summary: inout NotebookImportSummary) async -> [Item] {
        var items: [Item] = []
        for source in sources {
            if let format = NotebookFileFormat(fileExtension: source.pathExtension), !source.hasDirectoryPath {
                items.append(Item(location: source, format: format, folder: destination))
                continue
            }
            let folderName = source.lastPathComponent
            do {
                let listing = try NotebookLibraryListing.list(source)
                summary.otherFileCount += listing.otherFileCount
                guard !listing.notebooks.isEmpty else {
                    summary.foldersWithoutNotebooks.append(folderName)
                    continue
                }
                let folder = try await vault.freePath(destination, folderName, "")
                try await vault.makeFolder(folder)
                for notebook in listing.notebooks {
                    let notebookFolder = notebook.folderPath.isEmpty ? folder : try folder.appending(notebook.folderPath.joined(separator: "/"))
                    items.append(Item(location: notebook.location, format: notebook.format, folder: notebookFolder))
                }
            } catch {
                summary.unreadableFolders.append(folderName)
            }
        }
        return items
    }

    private func convert(_ item: Item, progress: AsyncStream<NotebookImportProgress>.Continuation,
                         state: NotebookImportProgress) async -> NotebookImportOutcome.Result {
        do {
            let notebook = try OpenedNotebook.open(item.location, format: item.format, limits: limits)
            var pageState = state
            pageState.currentPageCount = notebook.sourcePageCount
            progress.yield(pageState)
            try await vault.makeFolder(item.folder)
            let stem = NotebookImportName.pdfStem(forNotebookFileName: item.location.lastPathComponent, fallback: Self.fallbackNotebookName)
            let pdf = try await vault.freePath(item.folder, stem, "pdf")
            let writing = try conversion.writePDF(of: notebook, to: try vault.location(pdf), strokeCreationDate: strokeCreationDate) { pagesDone in
                pageState.finishedPageCount = pagesDone
                progress.yield(pageState)
            }
            let recordings = await writeRecordings(of: notebook, besidePDFNamed: pdf.stem, in: item.folder)
            await vault.filesDidChange([pdf] + recordings)
            let report = conversion.report(of: notebook, writing: writing, copiedRecordingCount: recordings.count)
            return .imported(ImportedNotebook(pdf: pdf, recordings: recordings, report: report))
        } catch is CancellationError {
            return .notStarted
        } catch let failure as NotebookImportFailure {
            return .failed(failure)
        } catch {
            // A free name or a folder the vault could not give: nothing of this notebook was written.
            return .failed(.notWritten)
        }
    }

    /// Each recording beside the PDF, "<PDF name> - <recording name>.m4a"; the ones that could not be copied are left out.
    private func writeRecordings(of notebook: OpenedNotebook, besidePDFNamed pdfStem: String, in folder: VaultPath) async -> [VaultPath] {
        var written: [VaultPath] = []
        for (recordingIndex, recording) in notebook.recordings.recordings.enumerated() {
            let stem = pdfStem + Self.recordingNameSeparator + recording.name
            // A path the vault cannot give is a recording not copied, which the report counts.
            guard let path = try? await vault.freePath(folder, stem, ImportedRecording.fileExtension), // counted as not copied
                  let location = try? vault.location(path), // counted as not copied
                  conversion.writeRecording(at: recordingIndex, of: notebook, to: location) else { continue }
            written.append(path)
        }
        return written
    }
}
