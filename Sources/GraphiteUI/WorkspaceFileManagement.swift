import Foundation
import GraphiteCore
import GraphiteIndex

/// A move that changes links, waiting for the person to choose whether to update them.
struct PendingMove: Identifiable {
    let id = UUID()
    let path: VaultPath
    let destination: VaultPath
    let plan: LinkUpdatePlan
    /// Moves asked for while this question is open, such as the other items of a
    /// multi-item drop. They run in order once it is answered.
    let queuedMoves = QueuedMoves()
}

/// Shared by every copy of a `PendingMove`: the dialog answers with the copy it was
/// shown with, which may predate the moves queued behind it.
final class QueuedMoves {
    private(set) var requests: [(path: VaultPath, destination: VaultPath)] = []

    func append(_ path: VaultPath, to destination: VaultPath) {
        guard !requests.contains(where: { request in request.path == path && request.destination == destination }) else { return }
        requests.append((path, destination))
    }

    func removeAll() -> [(path: VaultPath, destination: VaultPath)] {
        defer { requests.removeAll() }
        return requests
    }
}

/// Text typed into an open note while its file was moving, for the note's new place.
private struct EditDuringMove {
    let newPath: VaultPath
    let text: String
    /// The note's file as it was just before the move, which the text was typed over;
    /// nil when it could not be read then.
    let revisionBeforeMove: FileRevision?
}

/// File explorer actions: new folders, renaming and moving with link updates, copies,
/// and deletion, following the vault's Obsidian settings.
extension WorkspaceModel {
    var fileOperations: VaultFileOperations? {
        guard let store, let index else { return nil }
        return VaultFileOperations(store: store, index: index)
    }

    func createFolder(named name: String, in directory: VaultPath) async {
        guard let store else { return }
        do {
            let folder = try await store.createFolder(named: name, in: directory)
            if !directory.rawValue.isEmpty { expandedFolders.insert(directory) }
            expandedFolders.insert(folder)
            await refreshDirectory()
        } catch { errorMessage = error.localizedDescription }
    }

    /// Renames a file (keeping its extension) or a folder.
    func rename(_ path: VaultPath, to newName: String) async {
        let isFolder = isDirectory(path)
        let trimmedName = newName.trimmingCharacters(in: .whitespaces)
        if let problem = FileNameRules.problem(with: trimmedName, isNote: !isFolder && DocumentKind(path: path) == .markdown) {
            errorMessage = problem
            return
        }
        let fileExtension = (path.name as NSString).pathExtension
        let fileName = isFolder || fileExtension.isEmpty ? trimmedName : trimmedName + "." + fileExtension
        guard fileName != path.name else { return }
        do { await move(path, to: try path.parent.appending(fileName)) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Moves a file or folder into `folder`, keeping its name.
    func move(_ path: VaultPath, into folder: VaultPath) async {
        guard !folder.isInside(path), folder != path.parent else { return }
        do { await move(path, to: try folder.appending(path.name)) }
        catch { errorMessage = error.localizedDescription }
    }

    /// Plans the link updates; asks first unless "Automatically update internal links" is on.
    func move(_ path: VaultPath, to destination: VaultPath) async {
        guard let fileOperations, !pathsBeingMoved.contains(path) else { return }
        // A drop of several items asks one question at a time; the rest wait for its answer,
        // and their links are planned only once the earlier moves are done.
        if let pendingMove {
            if pendingMove.path != path { pendingMove.queuedMoves.append(path, to: destination) }
            return
        }
        if isTakenByAnotherItem(destination, movingFrom: path) {
            errorMessage = "“\(destination.rawValue)” already exists."
            return
        }
        // Notes linking to the item are found through the index. Before its first scan
        // finishes, some would be missed and their links silently left broken.
        guard hasCompletedIndexScan else {
            errorMessage = "Graphite is still reading the vault, so the links to “\(path.name)” cannot be updated yet. Try again when reading has finished."
            return
        }
        pathsBeingMoved.insert(path)
        defer { pathsBeingMoved.remove(path) }
        do {
            let editedNotePaths = tabDocuments.values.compactMap(\.markdownSession).filter(\.hasUnsavedChanges).map(\.path)
            try await saveOpenDocuments()
            // Links just typed into those notes are planned only once the index has read them.
            if let index, let root = folderAccess?.root, !editedNotePaths.isEmpty { try await index.refresh(paths: editedNotePaths, root: root) }
            let plan = try await fileOperations.linkUpdates(forMoving: path, to: destination)
            if let pendingMove {
                // Another move asked its question while this one was being planned.
                pendingMove.queuedMoves.append(path, to: destination)
            } else if plan.changedLinkCount > 0 && !vaultSettings.updatesLinksAutomatically {
                pendingMove = PendingMove(path: path, destination: destination, plan: plan)
            } else {
                await completeMove(path, to: destination, plan: plan, updatesLinks: true)
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// The person's answer to "Update links?". The move is passed in: the dialog clears
    /// `pendingMove` as it closes, before its button's action runs. Dismissing the question
    /// without an answer cancels the moves queued behind it too.
    func resolve(_ pendingMove: PendingMove, updatesLinks: Bool, alwaysUpdates: Bool = false) async {
        if self.pendingMove?.id == pendingMove.id { self.pendingMove = nil }
        if alwaysUpdates {
            var settings = vaultSettings
            settings.updatesLinksAutomatically = true
            await updateVaultSettings(settings)
        }
        await completeMove(pendingMove.path, to: pendingMove.destination, plan: pendingMove.plan, updatesLinks: updatesLinks)
        // A queued move that needs its own question asks it, and the rest queue behind that one.
        for request in pendingMove.queuedMoves.removeAll() { await move(request.path, to: request.destination) }
    }

    private func completeMove(_ path: VaultPath, to destination: VaultPath, plan: LinkUpdatePlan, updatesLinks: Bool) async {
        guard let fileOperations else { return }
        do {
            // Changes made while the question was open are saved before anything moves.
            try await saveOpenDocuments()
            let revisionsBeforeMove = await revisionsOfOpenNotes(inside: path)
            let report = try await fileOperations.move(path, to: destination, applying: updatesLinks ? plan : nil)
            // Read before the tabs let go of their sessions, with no suspension in between,
            // so every keystroke made during the move is kept.
            let editsDuringMove = unsavedEdits(inside: path, movedTo: destination, revisionsBeforeMove: revisionsBeforeMove)
            expandedFolders = Set(expandedFolders.map { folder in (try? folder.replacingPrefix(path, with: destination)) ?? folder })
            // Tabs of moved files load them again from their new place.
            followMoveInNavigation(from: path, to: destination)
            let (keptEditPaths, editProblems) = await saveEditsMadeDuringMove(editsDuringMove)
            // Without link updates the report lists only the moved item itself; the plan
            // lists every indexed file inside a moved folder.
            let movedFiles = report.moves.merging(plan.moves) { reportedDestination, _ in reportedDestination }
            refreshIndexAfterFileChanges(Array(movedFiles.keys) + Array(movedFiles.values) + report.updatedNotes + keptEditPaths)
            let changedNotes = Set(report.updatedNotes + keptEditPaths)
            for document in tabDocuments.values {
                if let session = document.markdownSession, changedNotes.contains(session.path) { await session.checkExternalChange() }
            }
            await refreshDirectory()
            var problems = editProblems
            if !report.failures.isEmpty {
                problems.append(Self.describeNotesNotUpdated(report.failures, movedItemName: destination.name))
            }
            if !problems.isEmpty { errorMessage = problems.joined(separator: "\n\n") }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Whether another file or folder already has `destination`'s name. A change of
    /// capitals alone names the same item on a case-insensitive volume, and is allowed.
    private func isTakenByAnotherItem(_ destination: VaultPath, movingFrom path: VaultPath) -> Bool {
        guard let root = folderAccess?.root, let destinationLocation = try? destination.url(in: root),
              FileManager.default.fileExists(atPath: destinationLocation.path) else { return false }
        guard let sourceLocation = try? path.url(in: root),
              let sourceIdentifier = try? sourceLocation.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier,
              let destinationIdentifier = try? destinationLocation.resourceValues(forKeys: [.fileResourceIdentifierKey]).fileResourceIdentifier
        else { return true }
        return !sourceIdentifier.isEqual(destinationIdentifier)
    }

    /// The file revisions of open notes inside `path`, just before it moves.
    private func revisionsOfOpenNotes(inside path: VaultPath) async -> [VaultPath: FileRevision] {
        guard let store else { return [:] }
        var revisions: [VaultPath: FileRevision] = [:]
        for session in tabDocuments.values.compactMap(\.markdownSession) where session.path.isInside(path) {
            // A note that cannot be read now has no revision to write over; text typed into
            // it during the move is kept as a separate copy instead.
            revisions[session.path] = try? await store.read(session.path, maximumBytes: MarkdownSession.maximumEditableBytes).revision
        }
        return revisions
    }

    /// Open notes inside the moved item with text not yet saved, typed while it moved.
    private func unsavedEdits(inside path: VaultPath, movedTo destination: VaultPath, revisionsBeforeMove: [VaultPath: FileRevision]) -> [EditDuringMove] {
        tabDocuments.values.compactMap(\.markdownSession).compactMap { session in
            guard session.path.isInside(path), session.hasUnsavedChanges,
                  let newPath = try? session.path.replacingPrefix(path, with: destination) else { return nil }
            return EditDuringMove(newPath: newPath, text: session.text, revisionBeforeMove: revisionsBeforeMove[session.path])
        }
    }

    /// Writes text typed during a move into the note at its new place. A note that the
    /// move itself changed (its own links were rewritten) keeps that version, and the typed
    /// text is saved beside it as a separate copy, so neither is lost.
    /// - Returns: The notes written, and a message for each edit saved as a copy or not saved.
    private func saveEditsMadeDuringMove(_ edits: [EditDuringMove]) async -> (writtenPaths: [VaultPath], problems: [String]) {
        guard let store else { return ([], []) }
        var writtenPaths: [VaultPath] = []
        var problems: [String] = []
        for edit in edits {
            let data = Data(edit.text.utf8)
            do {
                guard let revisionBeforeMove = edit.revisionBeforeMove else { throw GraphiteError.conflict }
                _ = try await store.save(data, at: edit.newPath, expecting: .revision(revisionBeforeMove))
                writtenPaths.append(edit.newPath)
            } catch {
                do {
                    let copyPath = try await store.uniquePath(directory: edit.newPath.parent, stem: edit.newPath.stem + " Graphite edits", extension: "md")
                    _ = try await store.save(data, at: copyPath, expecting: .absent)
                    writtenPaths.append(copyPath)
                    problems.append("“\(edit.newPath.name)” changed while it moved, so the text typed meanwhile was saved separately as “\(copyPath.name)”.")
                } catch {
                    problems.append("The text typed into “\(edit.newPath.name)” while it moved could not be saved. " + error.localizedDescription)
                }
            }
        }
        return (writtenPaths, problems)
    }

    /// The notes shown by name in the message; a folder move can leave many more.
    private static let maximumListedNotesNotUpdated = 20

    /// Which notes kept their old links, each with the reason `VaultFileOperations` gave.
    static func describeNotesNotUpdated(_ failures: [VaultPath: LinkUpdateFailure], movedItemName: String) -> String {
        let notes = failures.keys.sorted()
        var listedNotes = notes.prefix(maximumListedNotesNotUpdated).map { note in
            "“\(note.name)” (\(failures[note]?.explanation ?? "it could not be updated"))"
        }
        if notes.count > maximumListedNotesNotUpdated { listedNotes.append("\(notes.count - maximumListedNotesNotUpdated) more") }
        let noteCount = notes.count == 1 ? "1 note" : "\(notes.count) notes"
        return "“\(movedItemName)” was moved, but the links to it in \(noteCount) were not updated: " + listedNotes.joined(separator: "; ") + "."
    }

    func duplicate(_ path: VaultPath) async {
        guard let store else { return }
        do {
            try await saveOpenDocuments()
            let filesInFolder = isDirectory(path) ? (try await index?.paths(inside: path) ?? []) : []
            let copy = try await store.duplicate(path)
            // A copied folder's files are indexed one by one; the folder itself has no row.
            let copiedFiles = filesInFolder.isEmpty ? [copy] : filesInFolder.compactMap { file in try? file.replacingPrefix(path, with: copy) }
            refreshIndexAfterFileChanges(copiedFiles)
            await refreshDirectory()
            if !isDirectory(copy) { await open(copy) }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Deletes at once, or asks first when "Confirm file deletion" is on.
    func requestDeletion(of path: VaultPath) async {
        if vaultSettings.confirmsDeletion { pendingDeletion = path } else { await delete(path) }
    }

    func delete(_ path: VaultPath) async {
        guard let store else { return }
        do {
            // Edits still waiting for autosave are saved first: the copy in the trash is then
            // complete, and a deletion that fails loses nothing. The tabs close only once the
            // deletion succeeds (`forgetInNavigation`); a save attempted after that finds the
            // file gone and fails rather than bringing it back.
            try await saveDocuments(inside: path)
            let removedFiles = isDirectory(path) ? (try await index?.paths(inside: path) ?? []) : [path]
            // Copies first, with any unsaved edits: the vault's settings may delete permanently.
            await snapshotBeforeDeleting(removedFiles)
            let outcome = try await store.delete(path, method: vaultSettings.deletionMethod)
            expandedFolders = expandedFolders.filter { folder in !folder.isInside(path) }
            forgetInNavigation(path)
            refreshIndexAfterFileChanges(removedFiles)
            await refreshDirectory()
            if case .movedToVaultTrash = outcome, vaultSettings.deletionMethod == .systemTrash {
                errorMessage = "This storage has no system trash, so “\(path.name)” was moved to the vault's .trash folder instead."
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Opens every folder above the current file in the sidebar, showing the file list.
    func revealCurrentFile() {
        guard var folder = selection?.parent else { return }
        UserDefaults.standard.set(SidebarPanel.files.rawValue, forKey: SidebarPanelSettingKey.panel)
        searchQuery = ""
        while !folder.rawValue.isEmpty {
            expandedFolders.insert(folder)
            folder = folder.parent
        }
    }

    func collapseAllFolders() {
        expandedFolders.removeAll()
    }

    func isDirectory(_ path: VaultPath) -> Bool {
        guard let root = folderAccess?.root, let location = try? path.url(in: root) else { return false }
        return (try? location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    /// Saves the open notes and PDFs of `path` or of files inside it.
    private func saveDocuments(inside path: VaultPath) async throws {
        for document in tabDocuments.values where document.loadedPath?.isInside(path) == true { try await document.save() }
    }

    /// Refreshes the index rows of changed files; beyond a few hundred, one scan is cheaper.
    /// A scan already running may have passed these files, and starting another does
    /// nothing until it ends, so the rows are then refreshed one by one instead.
    private func refreshIndexAfterFileChanges(_ paths: [VaultPath]) {
        let uniquePaths = Array(Set(paths))
        if uniquePaths.count > Self.maximumIncrementalRefreshCount, !isIndexing { startIndexing() } else { refreshIndex(for: uniquePaths) }
    }
}
