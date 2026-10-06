import Foundation
import GraphiteCore
import GraphiteApple

/// What the Versions sheet opens on.
struct ConflictVersionsRequest: Identifiable {
    let id = UUID()
    let path: VaultPath
}

/// The versions a provider keeps beside a file, and the file as it was when they were
/// listed: a replacement is refused when the file has changed since.
struct ConflictVersionListing: Equatable, Sendable {
    let versions: [FileConflictVersion]
    let currentStamp: FileChangeStamp
}

/// Versions of a file that iCloud or another file provider kept after it was changed in
/// two places: finding the files that have them, and the three things the person can do
/// with one. Nothing here removes a version unless the person chose it.
extension WorkspaceModel {
    /// The most paths that wait to be checked. Beyond it the oldest requests are given
    /// up, so a huge folder cannot queue work without end; its files are checked again
    /// the next time they are listed or opened.
    static let maximumPendingConflictChecks = 5_000
    /// Files checked between two looks at whether the check is still wanted.
    static let conflictChecksPerBatch = 100

    // MARK: Finding

    /// Looks for kept versions of these files, off the main thread, and marks the files
    /// that have them. Only files the sidebar lists or a tab shows are ever asked about.
    func checkConflictVersions(of paths: some Sequence<VaultPath>) {
        guard folderAccess != nil else { return }
        var waitingPaths = Set(pendingConflictChecks)
        for path in paths where waitingPaths.insert(path).inserted { pendingConflictChecks.append(path) }
        if pendingConflictChecks.count > Self.maximumPendingConflictChecks {
            pendingConflictChecks.removeFirst(pendingConflictChecks.count - Self.maximumPendingConflictChecks)
        }
        guard conflictCheckTask == nil, !pendingConflictChecks.isEmpty else { return }
        conflictCheckTask = Task(priority: .utility) { [weak self] in await self?.runPendingConflictChecks() }
    }

    /// Forgets what is known and waiting, as when another vault opens.
    func resetConflictVersions() {
        conflictCheckTask?.cancel(); conflictCheckTask = nil
        pendingConflictChecks = []
        if !conflictedPaths.isEmpty { conflictedPaths = [] }
        conflictVersionsRequest = nil
    }

    private func runPendingConflictChecks() async {
        while !pendingConflictChecks.isEmpty, !Task.isCancelled {
            guard let root = folderAccess?.root else { break }
            let batch = Array(pendingConflictChecks.prefix(Self.conflictChecksPerBatch))
            pendingConflictChecks.removeFirst(batch.count)
            let states = await Self.conflictStates(of: batch, root: root, store: conflictVersionStore)
            // Another vault may have opened meanwhile; its check starts afresh.
            guard !Task.isCancelled, folderAccess?.root == root else { return }
            apply(states)
        }
        conflictCheckTask = nil
    }

    /// Asks the provider about each file. Runs off the main actor; stops between files
    /// once it is cancelled.
    private nonisolated static func conflictStates(of paths: [VaultPath], root: URL, store: any ConflictVersionStore) async -> [VaultPath: Bool] {
        var states: [VaultPath: Bool] = [:]
        for path in paths {
            guard !Task.isCancelled else { break }
            guard let location = try? path.url(in: root) else { continue }
            states[path] = store.hasConflictVersions(at: location)
        }
        return states
    }

    private func apply(_ states: [VaultPath: Bool]) {
        var updatedPaths = conflictedPaths
        for (path, hasConflictVersions) in states {
            if hasConflictVersions { updatedPaths.insert(path) } else { updatedPaths.remove(path) }
        }
        // Rows and banners read the set, so it changes only when its content does.
        if updatedPaths != conflictedPaths { conflictedPaths = updatedPaths }
    }

    /// Keeps the marks on a moved file or folder, and drops those of a deleted one.
    func followMoveInConflictVersions(from oldPath: VaultPath, to newPath: VaultPath?) {
        let affectedPaths = conflictedPaths.filter { path in path.isInside(oldPath) }
        guard !affectedPaths.isEmpty else { return }
        var updatedPaths = conflictedPaths.subtracting(affectedPaths)
        if let newPath {
            updatedPaths.formUnion(affectedPaths.compactMap { path in try? path.replacingPrefix(oldPath, with: newPath) })
        }
        conflictedPaths = updatedPaths
    }

    // MARK: Listing and reading

    /// The versions kept beside a file. Edits in an open tab are saved first, so the
    /// current version is what the person sees in the editor.
    func conflictVersionListing(of path: VaultPath) async throws -> ConflictVersionListing {
        guard let root = folderAccess?.root else { throw GraphiteError.unavailable("No vault is open.") }
        try await saveOpenDocument(at: path)
        let location = try path.url(in: root)
        let conflictVersionStore = conflictVersionStore
        let listing = try await Task.detached(priority: .userInitiated) {
            // The stamp first: a change between the two reads then refuses a replacement.
            let currentStamp = FileChangeStamp.of(location)
            return ConflictVersionListing(versions: try conflictVersionStore.conflictVersions(of: location), currentStamp: currentStamp)
        }.value
        apply([path: !listing.versions.isEmpty])
        return listing
    }

    /// Where a version's contents can be read; the provider downloads them when needed.
    func contentsLocation(of version: FileConflictVersion, ofFileAt path: VaultPath) async throws -> URL {
        guard let root = folderAccess?.root else { throw GraphiteError.unavailable("No vault is open.") }
        let location = try path.url(in: root)
        let conflictVersionStore = conflictVersionStore
        return try await Task.detached(priority: .userInitiated) { try conflictVersionStore.contentsLocation(ofVersion: version.id, ofFileAt: location) }.value
    }

    // MARK: Deciding

    /// Keeps the current file and removes `versions`, which the person chose to let go.
    func keepCurrentVersion(of path: VaultPath, removing versions: [FileConflictVersion]) async throws {
        guard let store, let root = folderAccess?.root else { throw GraphiteError.unavailable("No vault is open.") }
        let location = try path.url(in: root)
        let conflictVersionStore = conflictVersionStore, writer = store.writer
        let versionIdentifiers = versions.map(\.id)
        try await Task.detached(priority: .userInitiated) {
            try conflictVersionStore.removeVersions(versionIdentifiers, ofFileAt: location, using: writer)
        }.value
        await refreshConflictState(of: path)
    }

    /// Replaces the current file with `version`. The current contents are not kept, which
    /// the person confirmed; the other versions stay until they are decided about too.
    /// Throws `GraphiteError.conflict` when the file changed since `listing` was made.
    func replaceCurrentVersion(of path: VaultPath, with version: FileConflictVersion, listedIn listing: ConflictVersionListing) async throws {
        guard let store, let root = folderAccess?.root else { throw GraphiteError.unavailable("No vault is open.") }
        // Edits made since the listing are saved, which changes the file, so the
        // replacement is refused below and the person sees them compared first.
        try await saveOpenDocument(at: path)
        let location = try path.url(in: root)
        let conflictVersionStore = conflictVersionStore, writer = store.writer
        let replacedLocation = try await Task.detached(priority: .userInitiated) {
            try conflictVersionStore.replaceFile(at: location, withVersion: version.id, expecting: listing.currentStamp, using: writer)
        }.value
        await filesDidChangeByResolvingVersions([path] + [vaultPath(for: replacedLocation)].compactMap { replacedPath in replacedPath })
        await refreshConflictState(of: path)
    }

    /// Keeps `version` as a file of its own beside the current one, named as a conflict
    /// copy, and returns its path. The current file is untouched.
    func keepAsSeparateFile(_ version: FileConflictVersion, of path: VaultPath) async throws -> VaultPath {
        guard let store, let root = folderAccess?.root else { throw GraphiteError.unavailable("No vault is open.") }
        let stem = ConflictCopyName.stem(forVersionOf: path.stem, deviceName: version.deviceName, date: version.modified,
                                         isNote: DocumentKind(path: path) == .markdown)
        // The extension as the file spells it.
        let copyPath = try await store.uniquePath(directory: path.parent, stem: stem, extension: (path.name as NSString).pathExtension)
        let location = try path.url(in: root), copyLocation = try copyPath.url(in: root)
        let conflictVersionStore = conflictVersionStore, writer = store.writer
        try await Task.detached(priority: .userInitiated) {
            try conflictVersionStore.keepVersion(version.id, ofFileAt: location, asSeparateFileAt: copyLocation, using: writer)
        }.value
        await filesDidChangeByResolvingVersions([copyPath])
        await refreshConflictState(of: path)
        return copyPath
    }

    /// Graphite's own coordinated writes send no external-change notice, so the sidebar,
    /// the index, and open tabs of these files take the change here, through the path
    /// that handles a change made by another app.
    private func filesDidChangeByResolvingVersions(_ paths: [VaultPath]) async {
        await refreshDirectory()
        refreshIndex(for: paths)
        await checkOpenDocumentsForExternalChanges(limitedTo: Set(paths))
        // Images and embeds of the file show its new contents.
        drawingVersion += 1
    }

    private func refreshConflictState(of path: VaultPath) async {
        guard let root = folderAccess?.root else { return }
        apply(await Self.conflictStates(of: [path], root: root, store: conflictVersionStore))
    }

    private func saveOpenDocument(at path: VaultPath) async throws {
        for document in tabDocuments.values where document.loadedPath == path { try await document.save() }
    }
}
