import Foundation
import GRDB
import GraphiteCore

/// A link written in a note, with the file it reaches.
public struct ResolvedNoteLink: Hashable, Sendable {
    /// As the index stores it: a Wikilink's written target, or a Markdown link's vault path.
    public let target: String
    /// The one file the link reaches; nil when it reaches none, or could mean several.
    public let destination: VaultPath?
    public let isEmbed: Bool
    /// Written in a property value rather than in the note's text.
    public let isInProperties: Bool

    public init(target: String, destination: VaultPath?, isEmbed: Bool, isInProperties: Bool) {
        self.target = target
        self.destination = destination
        self.isEmbed = isEmbed
        self.isInProperties = isInProperties
    }
}

/// A Markdown note as the index last read it, with what a copy of the vault kept outside
/// Graphite needs beyond a base's record.
public struct IndexedNote: Sendable {
    public let record: BaseFileRecord
    public let aliases: [String]
    /// The `noteRevisions` entry the record was read with.
    public let revision: String
}

/// Reads for copies of the vault kept elsewhere, such as the PostgreSQL Mirror: which notes
/// changed, what each one holds, and where its links lead.
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

    /// A value that changes when the files or the aliases links resolve against change: while
    /// it stays the same, a note's links resolve as they did, unless the note itself changed.
    /// It is a hash, comparable only within one run of the app.
    public func linkResolutionState() throws -> Int {
        try databaseQueue.read { database in
            var hasher = Hasher()
            let paths = try String.fetchCursor(database, sql: "SELECT path FROM files ORDER BY path")
            while let path = try paths.next() { hasher.combine(path) }
            // A separator, so a path cannot pass for an alias.
            hasher.combine(0)
            let aliases = try Row.fetchCursor(database, sql: "SELECT alias, path FROM aliases ORDER BY path, alias")
            while let row = try aliases.next() {
                hasher.combine(row["alias"] as String)
                hasher.combine(row["path"] as String)
            }
            return hasher.finalize()
        }
    }

    /// The links to files in the vault of the notes at `paths`, or of every note when `paths`
    /// is nil, in the order the index stored them (the note's text, then its properties), each
    /// resolved as the graph resolves it. Web pages and other apps' links are left out, as the
    /// graph leaves them out. A note without such links has no entry.
    public func resolvedLinks(ofNotesAt paths: [String]? = nil) throws -> [String: [ResolvedNoteLink]] {
        try databaseQueue.read { database in
            let resolver = try GraphLinkResolver(database: database)
            // A link resolves the same way from every note in one folder.
            var destinationsByKey: [String: VaultPath?] = [:]
            func destination(of target: String, from source: VaultPath, isWiki: Bool) -> VaultPath? {
                let cacheKey = (isWiki ? "w" : "m") + source.parent.rawValue + "\u{0}" + target
                if let cached = destinationsByKey[cacheKey] { return cached }
                let resolved = resolver.resolve(target, from: source, isWiki: isWiki)
                let onlyDestination = resolved.count == 1 ? resolved.first : nil
                let destination = onlyDestination.flatMap { path in try? VaultPath(path) } // A stored path that is not valid is no destination.
                destinationsByKey[cacheKey] = destination
                return destination
            }
            var linksByNote: [String: [ResolvedNoteLink]] = [:]
            func add(source sourceText: String, target: String, isWiki: Bool, isEmbed: Bool, isInProperties: Bool) {
                guard !target.isEmpty, !Self.isExternalLink(target),
                      let source = try? VaultPath(sourceText) else { return } // A note path that is not valid has no links to copy.
                linksByNote[sourceText, default: []].append(ResolvedNoteLink(target: target, destination: destination(of: target, from: source, isWiki: isWiki),
                                                                            isEmbed: isEmbed, isInProperties: isInProperties))
            }
            // Every note's links, or one chunk of notes at a time through the indexes on `source` and `path`.
            let chunks: [(condition: String, arguments: StatementArguments)]
            if let paths {
                chunks = stride(from: 0, to: paths.count, by: Self.copiedNoteChunkSize).map { chunkStart in
                    let chunk = Array(paths[chunkStart..<min(chunkStart + Self.copiedNoteChunkSize, paths.count)])
                    return ("IN (" + Array(repeating: "?", count: chunk.count).joined(separator: ",") + ")", StatementArguments(chunk))
                }
            } else {
                chunks = [("LIKE '%.md'", StatementArguments())]
            }
            for chunk in chunks {
                let textLinksSelection = "SELECT source, target, isWiki, isEmbed FROM links WHERE source \(chunk.condition) ORDER BY rowid"
                let textLinks = try Row.fetchCursor(database, sql: textLinksSelection, arguments: chunk.arguments)
                while let row = try textLinks.next() {
                    add(source: row["source"], target: row["target"], isWiki: row["isWiki"], isEmbed: row["isEmbed"], isInProperties: false)
                }
            }
            // Property links are read as Wikilinks, as the graph reads them.
            for chunk in chunks {
                let propertyLinks = try Row.fetchCursor(database, sql: "SELECT path, target FROM property_links WHERE path \(chunk.condition) ORDER BY rowid",
                                                        arguments: chunk.arguments)
                while let row = try propertyLinks.next() {
                    add(source: row["path"], target: row["target"], isWiki: true, isEmbed: false, isInProperties: true)
                }
            }
            return linksByNote
        }
    }

    /// Paths per `IN (…)` statement when reading copied notes' revisions and aliases.
    private static let copiedNoteChunkSize = 500

    private static func revision(size: Int, modified: Double, contentIndexed: Bool) -> String {
        "\(size):\(modified):\(contentIndexed ? 1 : 0)"
    }
}
