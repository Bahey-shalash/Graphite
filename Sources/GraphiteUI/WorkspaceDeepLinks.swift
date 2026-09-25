import Foundation
import GraphiteCore

/// `graphite://` links from other apps, with Obsidian's actions (see `VaultURI`).
extension WorkspaceModel {
    func handle(_ url: URL) async {
        guard let link = VaultURI(url: url) else {
            errorMessage = "Graphite can't open this link: \(url.absoluteString)"
            return
        }
        if case .open(_, let path?) = link.action {
            await openFileSystemPath(path)
            return
        }
        if let vaultName = link.vault, !isCurrentVault(named: vaultName) {
            guard let vault = knownVault(named: vaultName) else {
                errorMessage = "No vault named “\(vaultName)” is in Graphite's vault list. Open its folder once from the vault list, then try the link again."
                return
            }
            do { try await openVault(vault) } catch {
                errorMessage = "Graphite couldn't open “\(vault.name)”. " + error.localizedDescription
                return
            }
        }
        guard store != nil else {
            errorMessage = "Open a vault first, then try the link again."
            return
        }
        switch link.action {
        case .open(let file, _):
            if let file { await openLinkedFile(file) }
        case .search(let query):
            searchQuery = query
            searchFocusRequest += 1
        case .new(let name, let file, let content, let opensNote, let mode):
            await createNoteFromLink(name: name, file: file, content: content, opensNote: opensNote, mode: mode)
        case .daily:
            await openDailyNote()
        }
    }

    /// Obsidian's "Copy Obsidian URL": a link that opens this file from any app.
    func openingLink(to path: VaultPath) -> String {
        VaultURI.openingLink(to: path, inVaultNamed: title)
    }

    // MARK: Private

    private func isCurrentVault(named name: String) -> Bool {
        guard let currentVaultIdentifier else { return false }
        return knownVault(named: name)?.id == currentVaultIdentifier
    }

    /// The vault a link names: by identifier, then by its folder's name, then ignoring capitals.
    private func knownVault(named name: String) -> KnownVault? {
        let vaults = vaultLibrary.vaults
        return vaults.first { vault in vault.id.uuidString.caseInsensitiveCompare(name) == .orderedSame }
            ?? vaults.first { vault in vault.name == name }
            ?? vaults.first { vault in vault.name.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Opens a note given as `file=`, resolved as a link from the vault's top: a name, a
    /// path, with a heading or block. It is never created, unlike following a link.
    private func openLinkedFile(_ file: String) async {
        guard let index, let topLevelSource = try? VaultPath("Link.md") else { return }
        do {
            var matches = try await index.resolve(file, from: topLevelSource)
            // A link that starts Graphite may arrive before the vault is read.
            var waited = 0
            while matches.isEmpty && !hasCompletedIndexScan && waited < 40 {
                try await Task.sleep(for: .milliseconds(250))
                waited += 1
                matches = try await index.resolve(file, from: topLevelSource)
            }
            guard !matches.isEmpty else {
                errorMessage = "No file in “\(title)” matches “\(WikiLinkResolver.pathPart(file))”."
                return
            }
            await follow(file, from: topLevelSource)
        } catch is CancellationError {
        } catch { errorMessage = error.localizedDescription }
    }

    /// `open?path=`: a full path, inside the vault that is open or another known vault.
    private func openFileSystemPath(_ fileSystemPath: String) async {
        let standardized = URL(fileURLWithPath: fileSystemPath).standardizedFileURL.resolvingSymlinksInPath().path
        func vaultPath(inside root: String) -> VaultPath? {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            guard standardized.hasPrefix(prefix) else { return nil }
            return try? VaultPath(String(standardized.dropFirst(prefix.count)))
        }
        if let root = folderAccess?.root.standardizedFileURL.resolvingSymlinksInPath().path, let path = vaultPath(inside: root) {
            await open(path)
            return
        }
        guard let vault = vaultLibrary.vaults.first(where: { vault in vaultPath(inside: vault.lastKnownPath) != nil }),
              let path = vaultPath(inside: vault.lastKnownPath) else {
            errorMessage = "“\(fileSystemPath)” is not in a vault Graphite knows."
            return
        }
        do {
            try await openVault(vault)
            await open(path)
        } catch { errorMessage = "Graphite couldn't open “\(vault.name)”. " + error.localizedDescription }
    }

    private func createNoteFromLink(name: String?, file: String?, content: String, opensNote: Bool, mode: VaultURI.NewNoteMode) async {
        guard let store else { return }
        do {
            var path: VaultPath
            if let file {
                path = try VaultPath(file.lowercased().hasSuffix(".md") ? file : file + ".md")
                if let problem = FileNameRules.problem(with: path.stem, isNote: true) { throw GraphiteError.unavailable(problem) }
            } else {
                let noteName = name ?? "Untitled"
                if let problem = FileNameRules.problem(with: noteName, isNote: true) { throw GraphiteError.unavailable(problem) }
                path = try newFileDirectory(nil).appending(noteName + ".md")
            }
            if try await store.fileExists(path) {
                switch mode {
                case .unique:
                    path = try await store.uniquePath(directory: path.parent, stem: path.stem, extension: "md")
                    _ = try await store.save(Data(content.utf8), at: path, expecting: .absent)
                case .append, .overwrite:
                    try await replaceText(of: path, keepingCopy: mode == .overwrite) { existing in
                        mode == .append ? VaultURI.appending(content, to: existing) : content
                    }
                }
            } else {
                try await store.createDirectory(path.parent)
                _ = try await store.save(Data(content.utf8), at: path, expecting: .absent)
                await refreshDirectory()
            }
            refreshIndex(for: [path])
            if opensNote { await open(path) }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Changes a note's text through its editor when it is open, so it can be undone, and
    /// otherwise in the file if it has not changed since it was read.
    private func replaceText(of path: VaultPath, keepingCopy: Bool, _ change: (String) -> String) async throws {
        guard let store else { return }
        if let session = openMarkdownSession(at: path) {
            if keepingCopy, let fileRecovery { _ = try? fileRecovery.takeSnapshot(of: session.text, for: path, minimumInterval: 0) }
            let changed = change(session.text)
            session.apply(MarkdownTextEdit(range: NSRange(location: 0, length: (session.text as NSString).length), replacement: changed,
                                           selectionAfter: NSRange(location: (changed as NSString).length, length: 0)))
            if !session.isEditorAttached { try await session.save() }
            return
        }
        let snapshot = try await store.read(path, maximumBytes: MarkdownSession.maximumEditableBytes)
        guard let existing = String(data: snapshot.data, encoding: .utf8) else { throw GraphiteError.invalidFile("“\(path.name)” is not UTF-8 text.") }
        if keepingCopy, let fileRecovery { _ = try? fileRecovery.takeSnapshot(of: existing, for: path, minimumInterval: 0) }
        _ = try await store.save(Data(change(existing).utf8), at: path, expecting: .revision(snapshot.revision))
    }
}
