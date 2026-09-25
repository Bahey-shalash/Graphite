import Foundation
import GraphiteCore

/// Obsidian's File recovery for the open vault: copies of notes taken before their saved
/// text is replaced, and before they are deleted, kept outside the vault.
extension WorkspaceModel {
    var snapshotInterval: TimeInterval { TimeInterval(preferences.snapshotIntervalMinutes * 60) }

    /// Whether a file is still in the vault, for notes known only from their copies.
    func isInVault(_ path: VaultPath) -> Bool {
        guard let root = folderAccess?.root, let location = try? path.url(in: root) else { return false }
        return FileManager.default.fileExists(atPath: location.path)
    }

    /// Keeps a copy of a note's saved text when a save or a reload is about to replace it.
    func watchForRecovery(_ session: MarkdownSession) {
        let path = session.path
        session.willReplaceSavedText = { [weak self] replacedText in
            guard let self, self.preferences.isEnabled(.fileRecovery), let fileRecovery = self.fileRecovery else { return }
            let interval = self.snapshotInterval
            Task.detached(priority: .utility) {
                _ = try? fileRecovery.takeSnapshot(of: replacedText, for: path, minimumInterval: interval)
            }
        }
    }

    /// Copies notes about to be deleted, whatever the interval, since the deletion may be permanent.
    func snapshotBeforeDeleting(_ paths: [VaultPath]) async {
        guard preferences.isEnabled(.fileRecovery), let fileRecovery, let store else { return }
        for path in paths.prefix(Self.maximumNotesCopiedBeforeDeletion) where DocumentKind(path: path) == .markdown {
            let text: String?
            if let session = openMarkdownSession(at: path) { text = session.text }
            else { text = (try? await store.read(path, maximumBytes: FileRecoveryStore.maximumSnapshotBytes)).flatMap { snapshot in String(data: snapshot.data, encoding: .utf8) } }
            guard let text else { continue }
            _ = try? await Task.detached(priority: .userInitiated) { try fileRecovery.takeSnapshot(of: text, for: path, minimumInterval: 0) }.value
        }
    }

    private static var maximumNotesCopiedBeforeDeletion: Int { 500 }

    /// Removes copies older than the history length, in the background.
    func pruneRecoverySnapshots() {
        guard let fileRecovery else { return }
        let historyLength = TimeInterval(preferences.snapshotHistoryDays * 86_400)
        Task.detached(priority: .background) { try? fileRecovery.pruneSnapshots(olderThan: historyLength) }
    }

    /// Puts a snapshot's text back: through the note's editor when it is open, so it can be
    /// undone; otherwise into the file, which is created again if it was deleted. The
    /// version being replaced is copied first.
    func restore(_ snapshot: FileRecoveryStore.Snapshot, of path: VaultPath) async {
        guard let store, let fileRecovery else { return }
        do {
            let text = try fileRecovery.text(of: snapshot)
            if let session = openMarkdownSession(at: path) {
                _ = try? fileRecovery.takeSnapshot(of: session.text, for: path, minimumInterval: 0)
                let length = (session.text as NSString).length
                session.apply(MarkdownTextEdit(range: NSRange(location: 0, length: length), replacement: text, selectionAfter: NSRange(location: 0, length: 0)))
                await open(path)
                return
            }
            if try await store.fileExists(path) {
                let current = try await store.read(path, maximumBytes: MarkdownSession.maximumEditableBytes)
                if let currentText = String(data: current.data, encoding: .utf8) { _ = try? fileRecovery.takeSnapshot(of: currentText, for: path, minimumInterval: 0) }
                _ = try await store.save(Data(text.utf8), at: path, expecting: .revision(current.revision))
            } else {
                try await store.createDirectory(path.parent)
                _ = try await store.save(Data(text.utf8), at: path, expecting: .absent)
                await refreshDirectory()
            }
            refreshIndex(for: [path])
            await open(path)
        } catch { errorMessage = error.localizedDescription }
    }
}
