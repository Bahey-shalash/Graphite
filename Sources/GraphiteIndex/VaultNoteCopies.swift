import Foundation
import GRDB
import GraphiteCore

/// A Markdown note as the index last read it, with what a copy of the vault kept outside
/// Graphite needs beyond a base's record.
public struct IndexedNote: Sendable {
    public let record: BaseFileRecord
    public let aliases: [String]
    /// The `noteRevisions` entry the record was read with.
    public let revision: String
}

/// Reads for copies of the vault kept elsewhere, such as the PostgreSQL Mirror: which notes
/// changed and what each one holds.
extension VaultIndex {
    /// Notes are the Markdown files; attachments, canvases and bases are not copied.
    /// SQLite's `LIKE` ignores the case of ASCII letters, so `.MD` is a note too.
    private static let markdownCondition = "path LIKE '%.md'"

    /// Every Markdown note with a revision that changes whenever the index reads the note's
    /// file again: its size, its modification date, and whether its contents were read yet.
    public func noteRevisions() throws -> [String: String] {
        try databaseQueue.read { database in
            var revisions: [String: String] = [:]
            let rows = try Row.fetchCursor(database, sql: "SELECT path, size, modified, contentIndexed FROM files WHERE \(Self.markdownCondition)")
            while let row = try rows.next() {
                revisions[row["path"]] = Self.revision(size: row["size"], modified: row["modified"], contentIndexed: row["contentIndexed"])
            }
            return revisions
        }
    }

    /// The notes at `paths` that the index holds, in that order, each with its aliases and the
    /// revision it was read with. One read, so a note and its revision always agree.
    public func indexedNotes(atPaths paths: [String]) throws -> [IndexedNote] {
        try databaseQueue.read { database in
            let records = try Self.records(forPaths: paths, in: database)
            var revisions: [String: String] = [:]
            var aliasesByPath: [String: [String]] = [:]
            for chunkStart in stride(from: 0, to: paths.count, by: Self.copiedNoteChunkSize) {
                let chunk = Array(paths[chunkStart..<min(chunkStart + Self.copiedNoteChunkSize, paths.count)])
                let placeholders = Array(repeating: "?", count: chunk.count).joined(separator: ",")
                for row in try Row.fetchAll(database, sql: "SELECT path, size, modified, contentIndexed FROM files WHERE path IN (\(placeholders))",
                                            arguments: StatementArguments(chunk)) {
                    revisions[row["path"]] = Self.revision(size: row["size"], modified: row["modified"], contentIndexed: row["contentIndexed"])
                }
                for row in try Row.fetchAll(database, sql: "SELECT path, alias FROM aliases WHERE path IN (\(placeholders)) ORDER BY rowid",
                                            arguments: StatementArguments(chunk)) {
                    aliasesByPath[row["path"], default: []].append(row["alias"])
                }
            }
            return records.compactMap { record in
                guard let revision = revisions[record.path.rawValue] else { return nil }
                return IndexedNote(record: record, aliases: aliasesByPath[record.path.rawValue] ?? [], revision: revision)
            }
        }
    }

    /// Paths per `IN (…)` statement when reading copied notes' revisions and aliases.
    private static let copiedNoteChunkSize = 500

    private static func revision(size: Int, modified: Double, contentIndexed: Bool) -> String {
        "\(size):\(modified):\(contentIndexed ? 1 : 0)"
    }
}
