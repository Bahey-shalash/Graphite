import Foundation
import GraphiteCore
import GraphiteIndex

/// A request to show a file in the sidebar's file list, drained by the sidebar. Each request
/// is new, so revealing the same file twice scrolls to it twice.
struct FileRevealRequest: Equatable {
    let path: VaultPath
    let token = UUID()
}

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

/// What a request to move or rename an item came to.
enum FileMoveOutcome: Equatable {
    /// The item is at its new place.
    case moved
    case refused(FileMoveRefusal)
    /// The person is asked whether to update links; the answer completes the move.
    case awaitingAnswer
    /// Another move's question is open; this move runs once it is answered.
    case queued
}

/// Why a move did not happen.
enum FileMoveRefusal: Equatable {
    case noVaultOpen
    case alreadyMoving
    case destinationTaken(VaultPath)
    case vaultStillBeingRead(movedName: String)
    /// The person dismissed the "Update links?" question without answering it.
    case cancelled(movedName: String)
    case failed(message: String)

    var message: String {
        switch self {
        case .noVaultOpen: "No vault is open."
        case .alreadyMoving: "The item is already being moved."
        case .destinationTaken(let destination): "“\(destination.rawValue)” already exists."
        case .vaultStillBeingRead(let movedName): "Graphite is still reading the vault, so the links to “\(movedName)” cannot be updated yet. Try again when reading has finished."
        case .cancelled(let movedName): "“\(movedName)” was not renamed."
        case .failed(let message): message
        }
    }
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

/// Changes made to an open note or canvas while its file was moving, for its new place.
private struct EditDuringMove {
    let newPath: VaultPath
    /// The whole file as the open document would save it.
    let data: Data
    /// The extension of the copy kept beside the moved file when it changed during the move.
    let copyExtension: String
    /// The file as it was just before the move, which the changes were made over;
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
    @discardableResult
    func move(_ path: VaultPath, to destination: VaultPath) async -> FileMoveOutcome {
        guard let fileOperations else { return .refused(.noVaultOpen) }
        guard !pathsBeingMoved.contains(path) else { return .refused(.alreadyMoving) }
        // A drop of several items asks one question at a time; the rest wait for its answer,
        // and their links are planned only once the earlier moves are done.
        if let pendingMove {
            if pendingMove.path == path { return .awaitingAnswer }
            pendingMove.queuedMoves.append(path, to: destination)
            return .queued
        }
        if isTakenByAnotherItem(destination, movingFrom: path) {
            let refusal = FileMoveRefusal.destinationTaken(destination)
            errorMessage = refusal.message
            return .refused(refusal)
        }
        // Notes linking to the item are found through the index. Before its first scan
        // finishes, some would be missed and their links silently left broken.
        guard hasCompletedIndexScan else {
            let refusal = FileMoveRefusal.vaultStillBeingRead(movedName: path.name)
            errorMessage = refusal.message
            return .refused(refusal)
        }
        pathsBeingMoved.insert(path)
        defer { pathsBeingMoved.remove(path) }
        do {
            let editedNotePaths = tabDocuments.values.compactMap(\.markdownSession).filter(\.hasUnsavedChanges).map(\.path)
                + tabDocuments.values.compactMap(\.canvasSession).filter(\.hasUnsavedChanges).map(\.path)
            try await saveOpenDocuments()
            // Links just typed into those notes are planned only once the index has read them.
            if let index, let root = folderAccess?.root, !editedNotePaths.isEmpty { try await index.refresh(paths: editedNotePaths, root: root) }
            let plan = try await fileOperations.linkUpdates(forMoving: path, to: destination)
            if let pendingMove {
                // Another move asked its question while this one was being planned.
                pendingMove.queuedMoves.append(path, to: destination)
                return .queued
            } else if plan.changedLinkCount > 0 && !vaultSettings.updatesLinksAutomatically {
                pendingMove = PendingMove(path: path, destination: destination, plan: plan)
                return .awaitingAnswer
            } else {
                return await completeMove(path, to: destination, plan: plan, updatesLinks: true)
            }
        } catch {
            errorMessage = error.localizedDescription
            return .refused(.failed(message: error.localizedDescription))
        }
    }

    /// The person's answer to "Update links?". The move is passed in: the dialog clears
    /// `pendingMove` as it closes, before its button's action runs. Dismissing the question
    /// without an answer cancels the moves queued behind it too.
    func resolve(_ pendingMove: PendingMove, updatesLinks: Bool, alwaysUpdates: Bool = false) async {
        if self.pendingMove?.id == pendingMove.id { self.pendingMove = nil }
        // Marked before the first suspension, so whoever waits for one of these moves never
        // sees it neither asked about nor moving while the answer is carried out.
        let answeredPaths = Set([pendingMove.path] + pendingMove.queuedMoves.requests.map { request in request.path })
        pathsMovingAfterAnswer.formUnion(answeredPaths)
        defer { pathsMovingAfterAnswer.subtract(answeredPaths) }
        if alwaysUpdates {
            var settings = vaultSettings
            settings.updatesLinksAutomatically = true
            await updateVaultSettings(settings)
        }
        answeredMoveOutcomes[pendingMove.path] = await completeMove(pendingMove.path, to: pendingMove.destination, plan: pendingMove.plan, updatesLinks: updatesLinks)
        // A queued move that needs its own question asks it, and the rest queue behind that one.
        for request in pendingMove.queuedMoves.removeAll() {
            let outcome = await move(request.path, to: request.destination)
            // A move that asks its own question is answered by a later `resolve`.
            if outcome != .awaitingAnswer && outcome != .queued { answeredMoveOutcomes[request.path] = outcome }
        }
    }

    private func completeMove(_ path: VaultPath, to destination: VaultPath, plan: LinkUpdatePlan, updatesLinks: Bool) async -> FileMoveOutcome {
        guard let fileOperations else { return .refused(.noVaultOpen) }
        do {
            // Changes made while the question was open are saved before anything moves.
            try await saveOpenDocuments()
            let revisionsBeforeMove = await revisionsOfOpenDocuments(inside: path)
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
                if let session = document.canvasSession, changedNotes.contains(session.path) { await session.checkExternalChange() }
            }
            await refreshDirectory()
            var problems = editProblems
            if !report.failures.isEmpty {
                problems.append(Self.describeNotesNotUpdated(report.failures, movedItemName: destination.name))
            }
            if !problems.isEmpty { errorMessage = problems.joined(separator: "\n\n") }
            return .moved
        } catch {
            errorMessage = error.localizedDescription
            return .refused(.failed(message: error.localizedDescription))
        }
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

    /// The file revisions of open notes and canvases inside `path`, just before it moves.
    private func revisionsOfOpenDocuments(inside path: VaultPath) async -> [VaultPath: FileRevision] {
        guard let store else { return [:] }
        var revisions: [VaultPath: FileRevision] = [:]
        for session in tabDocuments.values.compactMap(\.markdownSession) where session.path.isInside(path) {
            // A note that cannot be read now has no revision to write over; text typed into
            // it during the move is kept as a separate copy instead.
            revisions[session.path] = try? await store.read(session.path, maximumBytes: MarkdownSession.maximumEditableBytes).revision
        }
        for session in tabDocuments.values.compactMap(\.canvasSession) where session.path.isInside(path) {
            // As for a note: a canvas that cannot be read now is kept as a separate copy.
            revisions[session.path] = try? await store.read(session.path, maximumBytes: CanvasFile.maximumSourceBytes).revision
        }
        return revisions
    }

    /// Open notes and canvases inside the moved item with changes not yet saved, made while it moved.
    private func unsavedEdits(inside path: VaultPath, movedTo destination: VaultPath, revisionsBeforeMove: [VaultPath: FileRevision]) -> [EditDuringMove] {
        let noteEdits = tabDocuments.values.compactMap(\.markdownSession).compactMap { session -> EditDuringMove? in
            guard session.path.isInside(path), session.hasUnsavedChanges,
                  let newPath = try? session.path.replacingPrefix(path, with: destination) else { return nil }
            return EditDuringMove(newPath: newPath, data: NoteTextEncoding.encode(session.text, hasByteOrderMark: session.hasByteOrderMark),
                                  copyExtension: "md", revisionBeforeMove: revisionsBeforeMove[session.path])
        }
        let canvasEdits = tabDocuments.values.compactMap(\.canvasSession).compactMap { session -> EditDuringMove? in
            guard session.path.isInside(path), let newPath = try? session.path.replacingPrefix(path, with: destination) else { return nil }
            // Text typed into a card is part of the file only once committed.
            session.commitTextEdit()
            guard session.hasUnsavedChanges else { return nil }
            return EditDuringMove(newPath: newPath, data: session.file.data, copyExtension: "canvas", revisionBeforeMove: revisionsBeforeMove[session.path])
        }
        return noteEdits + canvasEdits
    }

    /// Writes changes made during a move into the note or canvas at its new place. A file
    /// that the move itself changed (a note's own links were rewritten) keeps that version,
    /// and the changes are saved beside it as a separate copy, so neither is lost.
    /// - Returns: The files written, and a message for each edit saved as a copy or not saved.
    private func saveEditsMadeDuringMove(_ edits: [EditDuringMove]) async -> (writtenPaths: [VaultPath], problems: [String]) {
        guard let store else { return ([], []) }
        var writtenPaths: [VaultPath] = []
        var problems: [String] = []
        for edit in edits {
            let data = edit.data
            do {
                guard let revisionBeforeMove = edit.revisionBeforeMove else { throw GraphiteError.conflict }
                _ = try await store.save(data, at: edit.newPath, expecting: .revision(revisionBeforeMove))
                writtenPaths.append(edit.newPath)
            } catch {
                do {
                    let copyPath = try await store.uniquePath(directory: edit.newPath.parent, stem: edit.newPath.stem + " Graphite edits", extension: edit.copyExtension)
                    _ = try await store.save(data, at: copyPath, expecting: .absent)
                    writtenPaths.append(copyPath)
                    problems.append("“\(edit.newPath.name)” changed while it moved, so the changes made meanwhile were saved separately as “\(copyPath.name)”.")
                } catch {
                    problems.append("The changes made to “\(edit.newPath.name)” while it moved could not be saved. " + error.localizedDescription)
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

    /// Makes a copy of each item beside it, as Make a Copy does for one, without opening any of
    /// the copies. An item whose copy fails is named in the message; the others are still copied.
    func duplicate(_ paths: [VaultPath]) async {
        guard let store, !paths.isEmpty else { return }
        do { try await saveOpenDocuments() } catch {
            errorMessage = "Open documents could not be saved before copying, so nothing was copied."
            return
        }
        var copiedFiles: [VaultPath] = []
        var failedNames: [String] = []
        for path in paths {
            do {
                let filesInFolder = isDirectory(path) ? (try await index?.paths(inside: path) ?? []) : []
                let copy = try await store.duplicate(path)
                // A copied file's path is always valid.
                let copiedInside = filesInFolder.compactMap { file in try? file.replacingPrefix(path, with: copy) } // Not valid: not indexed here.
                copiedFiles += filesInFolder.isEmpty ? [copy] : copiedInside
            } catch {
                failedNames.append("“\(path.name)”")
            }
        }
        refreshIndexAfterFileChanges(copiedFiles)
        await refreshDirectory()
        if !failedNames.isEmpty { errorMessage = "Could not make a copy of " + failedNames.joined(separator: ", ") + "." }
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
                notice = "This storage has no system trash, so “\(path.name)” was moved to the vault's .trash folder instead."
            }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Shows the current file in the sidebar's file list, wherever this is asked from: the
    /// Files panel in place of a search or a plugin's view, every folder above the file open,
    /// and a request that shows the sidebar and scrolls the list to the file.
    func revealCurrentFile() {
        guard let path = selection else { return }
        deviceDefaults.set(SidebarPanel.files.rawValue, forKey: SidebarPanelSettingKey.panel)
        searchQuery = ""
        communityPlugins.shownSidebarViewIdentifier = nil
        var folder = path.parent
        while !folder.rawValue.isEmpty {
            expandedFolders.insert(folder)
            folder = folder.parent
        }
        fileRevealRequest = FileRevealRequest(path: path)
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

extension WorkspaceModel {
    /// Copies files chosen outside the vault into `directory`, each under a free name, as
    /// Goodnotes' Import does. The originals stay where they are. A file of a type an importer
    /// of `DroppedFileImporters` takes goes to it; a text file becomes a note. A file that fails
    /// is reported; the others are still copied.
    func importFiles(from chosenSources: [URL], into directory: VaultPath) async {
        guard let store, let root = folderAccess?.root else { return }
        let routing = DroppedFileImporters.route(chosenSources, through: DroppedFileImporters.registered)
        for routed in routing.routed { await routed.importer.importFiles(routed.files, directory) }
        let sources = routing.remaining
        var importedPaths: [VaultPath] = []
        var failedNames: [String] = []
        for source in sources {
            let hasAccess = source.startAccessingSecurityScopedResource()
            defer { if hasAccess { source.stopAccessingSecurityScopedResource() } }
            do {
                try await store.createDirectory(directory)
                let stem = source.deletingPathExtension().lastPathComponent
                let fileExtension = ImportedFileName.fileExtension(forSourceExtension: source.pathExtension)
                let path = try await store.uniquePath(directory: directory, stem: stem, extension: fileExtension)
                let destination = try path.url(in: root)
                let writer = store.writer
                _ = try await Task.detached { try writer.copy(from: source, to: destination, expecting: .absent) }.value
                importedPaths.append(path)
            } catch {
                failedNames.append(source.lastPathComponent)
            }
        }
        if !importedPaths.isEmpty {
            refreshIndex(for: importedPaths)
            await refreshDirectory()
        }
        if !failedNames.isEmpty {
            errorMessage = "Could not import " + failedNames.map { name in "“\(name)”" }.joined(separator: ", ") + "."
        }
    }
}
