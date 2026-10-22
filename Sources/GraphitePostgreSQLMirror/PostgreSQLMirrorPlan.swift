import Foundation

/// What a note looks like in the database, as two digests: one of its row and one of its links.
struct CopiedNoteDigests: Hashable, Sendable {
    var contentDigest: String
    var linksDigest: String
}

/// What one copy changes in the database, from the notes the index holds now and the notes the
/// database holds. A note whose row and links are unchanged is not written again.
struct PostgreSQLMirrorPlan: Equatable, Sendable {
    /// Notes whose row is new or different, its links digest included; a note whose links
    /// digest differs has its links written again too.
    let notePathsToWrite: [String]
    /// Notes the database holds that the vault no longer has (deleted, or moved elsewhere).
    let notePathsToDelete: [String]

    init(indexedNotes: [String: CopiedNoteDigests], copiedNotes: [String: CopiedNoteDigests]) {
        notePathsToWrite = indexedNotes.compactMap { path, digests in copiedNotes[path] == digests ? nil : path }.sorted()
        notePathsToDelete = copiedNotes.keys.filter { path in indexedNotes[path] == nil }.sorted()
    }

    var isEmpty: Bool { notePathsToWrite.isEmpty && notePathsToDelete.isEmpty }
}
