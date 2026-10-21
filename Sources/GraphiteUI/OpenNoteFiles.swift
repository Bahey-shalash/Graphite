import Foundation

/// The notes open in the windows of the process, by file. A note open in two windows, or two
/// tabs, is one text: an edit in one shows in the other at once, and a save in either is the
/// saved state of both, so neither save overwrites the other or is refused as another app's
/// change (`MarkdownSession`). Sessions are held weakly and leave the list as they close.
@MainActor
final class OpenNoteFiles {
    private struct WeakSession {
        weak var session: MarkdownSession?
    }

    private var sessionsByFile: [String: [WeakSession]] = [:]

    /// The key of a file: its resolved path, the same whichever vault folder reached it.
    nonisolated static func key(for location: URL) -> String {
        location.resolvingSymlinksInPath().standardizedFileURL.path
    }

    /// Adds `session` to its file's sessions and returns one already open, whose text and
    /// saved state it takes.
    func register(_ session: MarkdownSession, file: String) -> MarkdownSession? {
        let openSessions = sessionsByFile[file, default: []].filter { entry in entry.session != nil }
        sessionsByFile[file] = openSessions + [WeakSession(session: session)]
        return openSessions.first?.session
    }

    /// The other open sessions of the file.
    func siblings(of session: MarkdownSession, file: String) -> [MarkdownSession] {
        guard let entries = sessionsByFile[file] else { return [] }
        return entries.compactMap(\.session).filter { sibling in sibling !== session }
    }
}
