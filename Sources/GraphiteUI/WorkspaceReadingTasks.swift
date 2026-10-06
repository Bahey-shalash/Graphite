import Foundation
import GraphiteCore

/// Ticking a task from reading view, as Obsidian does: in the note itself, or, for a task
/// of an embedded note, in that note.
extension WorkspaceModel {
    /// Ticks or unticks the task at `location` of `note`, which `session`'s reading view
    /// shows. False when the note no longer has the task there.
    func toggleReadingTask(at location: ReadingTasks.Location, in note: VaultPath, shownBy session: MarkdownSession) async -> Bool {
        if note == session.path { return session.toggleTask(at: location) }
        if let embeddedSession = openMarkdownSession(at: note) {
            guard embeddedSession.toggleTask(at: location) else { return false }
            // Reading view draws an embedded note from its file, so the change is saved
            // before the note that embeds it is drawn again.
            do { try await embeddedSession.save() } catch { errorMessage = error.localizedDescription }
            return true
        }
        guard let store else { return false }
        do {
            let snapshot = try await store.read(note, maximumBytes: MarkdownSession.maximumEditableBytes)
            guard let decoded = NoteTextEncoding.decode(snapshot.data),
                  let edit = ReadingTasks.togglingEdit(at: location, in: decoded.text, selection: NSRange(location: 0, length: 0)) else { return false }
            let tickedText = (decoded.text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
            _ = try await store.save(NoteTextEncoding.encode(tickedText, hasByteOrderMark: decoded.hasByteOrderMark), at: note, expecting: .revision(snapshot.revision))
            refreshIndex(for: [note])
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
