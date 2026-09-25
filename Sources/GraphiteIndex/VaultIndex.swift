import Foundation
import CryptoKit
import GRDB
import GraphiteCore

public struct IndexedFile: Sendable {
    public let path: VaultPath
    public let size: Int
    public let modified: Date
    /// Creation date for `file.ctime` in bases; the modification date when unknown.
    public let created: Date?
    public let markdown: String?
    /// The note was read and is not UTF-8 text. Its content cannot become searchable
    /// until the file changes, so an unchanged file is not read again on every scan.
    let isUnreadableAsText: Bool
    public init(path: VaultPath, size: Int, modified: Date, markdown: String?) {
        self.init(path: path, size: size, modified: modified, created: nil, markdown: markdown)
    }
    public init(path: VaultPath, size: Int, modified: Date, created: Date?, markdown: String?) {
        self.init(path: path, size: size, modified: modified, created: created, markdown: markdown, isUnreadableAsText: false)
    }
    init(path: VaultPath, size: Int, modified: Date, created: Date?, markdown: String?, isUnreadableAsText: Bool) {
        self.path = path; self.size = size; self.modified = modified; self.created = created; self.markdown = markdown
        self.isUnreadableAsText = isUnreadableAsText
    }
}

/// The `files.contentIndexed` column: whether a note's text is in the search table.
enum IndexedContentState: Int {
    /// Not read: not a note, too large, not downloaded, or reading failed. A readable
    /// note in this state is read again by the next scan.
    case notRead = 0
    case indexed = 1
    /// Read, but not UTF-8 text.
    case unreadableAsText = 2
}

public struct IndexingReport: Sendable {
    public let discoveredFiles: Int
    public let updatedFiles: Int
    public let pendingContentFiles: Int
    public let failedPaths: [String]
}

/// SQLite is an inventory and search cache. It never writes the user's documents.
public actor VaultIndex {
    /// Larger notes stay in the inventory but are not read for full-text search.
    public static let maximumIndexedNoteBytes = 8 * 1_048_576
    /// A write batch is flushed once it holds this much note text, as well as after
    /// `maximumBatchFileCount` files, so a folder of large notes keeps memory bounded.
    static let maximumBatchContentBytes = 4 * 1_048_576
    static let maximumBatchFileCount = 64
    /// Internal so the base record queries in `BaseRecordQueries.swift` share it.
    let databaseQueue: DatabaseQueue
    private var isScanning = false
    /// The generation of the scan in progress. `refresh` writes rows with it, so a note
    /// saved during a scan counts as seen and is not pruned when the scan ends.
    private var activeScanGeneration: String?
    /// Files `refresh` wrote or removed during the scan in progress, with the modification
    /// date it wrote (`distantFuture` for a removal). The scan may have read such a file
    /// earlier into a batch it has not written yet; that older reading must not replace them.
    private var pathsRefreshedDuringScan: [String: Date] = [:]
    /// Tables holding one or more rows per file, keyed by the file's path.
    static let perFileTables = ["aliases", "tags", "headings", "properties", "property_links"]
    /// Deletes the search rows of files a scan did not see. By row identity: the search
    /// table has no ordinary index on its path column, so deleting by path would read
    /// every row of it on every scan.
    static let staleSearchRowDeletion = "DELETE FROM search WHERE rowid IN (SELECT rowid FROM files WHERE generation != ?)"

    public init(databaseURL: URL) throws {
        try FileManager.default.createDirectory(at: databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        var configuration = Configuration()
        configuration.prepareDatabase { database in
            try database.execute(sql: "PRAGMA cache_size = -8192")
            try database.execute(sql: "PRAGMA journal_mode = WAL")
            database.add(function: RegularExpressionFunction.function)
        }
        databaseQueue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
        var migrator = DatabaseMigrator()
        migrator.registerMigration("inventory-and-links-1") { database in
            try database.execute(sql: """
                CREATE TABLE files (
                  path TEXT PRIMARY KEY, basename TEXT NOT NULL, title TEXT NOT NULL,
                  size INTEGER NOT NULL, modified REAL NOT NULL, generation TEXT NOT NULL,
                  contentIndexed INTEGER NOT NULL DEFAULT 0
                );
                CREATE INDEX files_basename ON files(basename COLLATE NOCASE);
                CREATE VIRTUAL TABLE search USING fts5(path, title, body, tokenize='unicode61 remove_diacritics 2');
                CREATE TABLE links (source TEXT NOT NULL, target TEXT NOT NULL, isWiki INTEGER NOT NULL, isEmbed INTEGER NOT NULL);
                CREATE INDEX links_source ON links(source);
                CREATE INDEX links_target ON links(target COLLATE NOCASE);
                CREATE TABLE aliases (alias TEXT NOT NULL, path TEXT NOT NULL);
                CREATE INDEX aliases_name ON aliases(alias COLLATE NOCASE);
                CREATE TABLE tags (tag TEXT NOT NULL, path TEXT NOT NULL);
                CREATE INDEX tags_name ON tags(tag COLLATE NOCASE);
                CREATE TABLE headings (heading TEXT NOT NULL, path TEXT NOT NULL);
                """)
        }
        migrator.registerMigration("bounded-update-lookups-2") { database in
            try database.execute(sql: """
                CREATE INDEX aliases_path ON aliases(path);
                CREATE INDEX tags_path ON tags(path);
                CREATE INDEX headings_path ON headings(path);
                """)
        }
        migrator.registerMigration("filename-search-and-row-identities-3") { database in
            try database.execute(sql: """
                CREATE VIRTUAL TABLE rebuilt_search USING fts5(path, title, body, tokenize='unicode61 remove_diacritics 2');
                INSERT INTO rebuilt_search(rowid, path, title, body)
                  SELECT files.rowid, files.path, search.title, search.body FROM files JOIN search ON files.path = search.path;
                DROP TABLE search;
                ALTER TABLE rebuilt_search RENAME TO search;
                """)
        }
        migrator.registerMigration("vault-path-markdown-link-targets-4") { database in
            // Link targets are stored differently now. The index is a disposable cache,
            // so it is emptied and the next scan rebuilds it from the vault.
            for table in ["search", "links", "aliases", "tags", "headings", "files"] { try database.execute(sql: "DELETE FROM \(table)") }
        }
        migrator.registerMigration("base-properties-and-creation-dates-5") { database in
            // Frontmatter for bases is stored as parsed YAML structure (JSON), not as
            // typed values: `.obsidian/types.json` can change without a rescan.
            try database.execute(sql: """
                CREATE TABLE properties (path TEXT NOT NULL, position INTEGER NOT NULL, key TEXT NOT NULL, node TEXT NOT NULL);
                CREATE INDEX properties_path ON properties(path);
                CREATE INDEX properties_key ON properties(key COLLATE NOCASE);
                CREATE TABLE property_links (path TEXT NOT NULL, target TEXT NOT NULL);
                CREATE INDEX property_links_path ON property_links(path);
                CREATE INDEX property_links_target ON property_links(target COLLATE NOCASE);
                ALTER TABLE files ADD COLUMN created REAL;
                """)
            // Rows written before this migration lack properties and creation dates. An
            // impossible size makes the next scan re-read every file, while existing
            // search rows keep working until then.
            try database.execute(sql: "UPDATE files SET size = -1")
        }
        migrator.registerMigration("unicode-name-keys-6") { database in
            // Names are matched by a normalized key, so a link finds a file whatever
            // Unicode form its name is stored in. Rows gain keys on the next scan.
            try database.execute(sql: """
                ALTER TABLE files ADD COLUMN path_key TEXT;
                ALTER TABLE files ADD COLUMN name_key TEXT;
                CREATE INDEX files_path_key ON files(path_key COLLATE NOCASE);
                CREATE INDEX files_name_key ON files(name_key COLLATE NOCASE);
                UPDATE files SET size = -1;
                """)
        }
        migrator.registerMigration("search-whole-note-text-7") { database in
            // Search now reads the whole note, properties included, and match positions
            // are positions in the file. Every note is read again on the next scan.
            try database.execute(sql: "UPDATE files SET size = -1")
        }
        migrator.registerMigration("case-folded-link-keys-8") { database in
            // SQLite's NOCASE and LIKE fold ASCII letters only, so `[[éclair]]` missed
            // `Éclair.md`. Keys folded in Swift (`foldedKey`) are stored and indexed for
            // exact lookups. Existing rows get them here, without a rescan. The NOCASE
            // indexes on `path_key` and `name_key` served only the lookups these replace,
            // so they are dropped rather than kept up to date on every write.
            database.add(function: Self.foldedKeyFunction)
            defer { database.remove(function: Self.foldedKeyFunction) }
            try database.execute(sql: """
                ALTER TABLE files ADD COLUMN folded_path TEXT;
                ALTER TABLE files ADD COLUMN folded_name TEXT;
                ALTER TABLE aliases ADD COLUMN folded_alias TEXT;
                ALTER TABLE links ADD COLUMN folded_target TEXT;
                ALTER TABLE property_links ADD COLUMN folded_target TEXT;
                UPDATE files SET folded_path = \(Self.foldedKeyFunctionName)(path), folded_name = \(Self.foldedKeyFunctionName)(basename);
                UPDATE aliases SET folded_alias = \(Self.foldedKeyFunctionName)(alias);
                UPDATE links SET folded_target = \(Self.foldedKeyFunctionName)(target);
                UPDATE property_links SET folded_target = \(Self.foldedKeyFunctionName)(target);
                CREATE INDEX files_folded_path ON files(folded_path);
                CREATE INDEX files_folded_name ON files(folded_name);
                CREATE INDEX aliases_folded_alias ON aliases(folded_alias);
                CREATE INDEX links_folded_target ON links(folded_target);
                CREATE INDEX property_links_folded_target ON property_links(folded_target);
                DROP INDEX files_path_key;
                DROP INDEX files_name_key;
                """)
        }
        migrator.registerMigration("markdown-link-written-targets-9") { database in
            // Markdown links are now stored as written (decoded) unless they are relative
            // to the note, so shortest and absolute-format links find their files. Every
            // note is read again on the next scan.
            try database.execute(sql: "UPDATE files SET size = -1")
        }
        try migrator.migrate(databaseQueue)
    }

    /// Text for matching names the way Obsidian does: ignoring case for every letter, not
    /// only ASCII, and whatever Unicode form the name is stored in.
    static func foldedKey(_ text: String) -> String {
        WikiLinkResolver.caseFoldedKey(text)
    }

    private static let foldedKeyFunctionName = "graphite_folded_key"
    private static let foldedKeyFunction = DatabaseFunction(foldedKeyFunctionName, argumentCount: 1, pure: true) { values in
        String.fromDatabaseValue(values[0]).map(foldedKey)
    }

    public static func cacheURL(for root: URL) throws -> URL {
        let directory = try FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let identifier = SHA256.hash(data: Data(root.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent("Graphite/Indexes/\(identifier).sqlite")
    }

    /// Where a vault's index lives: named after the vault's identifier in the vault list,
    /// so it survives the app's folder moving, as iOS may do on an update. An index named
    /// after `legacyRoot`'s path, as earlier versions named it, is moved there once, and
    /// indexes left unused for 30 days (by vaults removed or moved) are deleted.
    public static func cacheURL(forVault vaultIdentifier: UUID, legacyRoot: URL, in cachesDirectory: URL? = nil) throws -> URL {
        let caches = try cachesDirectory ?? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let directory = caches.appendingPathComponent("Graphite/Indexes", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let location = directory.appendingPathComponent(vaultIdentifier.uuidString + ".sqlite")
        let legacyName = SHA256.hash(data: Data(legacyRoot.standardizedFileURL.path.utf8)).map { String(format: "%02x", $0) }.joined()
        let legacyLocation = directory.appendingPathComponent(legacyName + ".sqlite")
        if !FileManager.default.fileExists(atPath: location.path), FileManager.default.fileExists(atPath: legacyLocation.path) {
            // The database and its journal move together, or not at all.
            for suffix in ["", "-wal", "-shm"] {
                let source = URL(fileURLWithPath: legacyLocation.path + suffix)
                guard FileManager.default.fileExists(atPath: source.path) else { continue }
                try? FileManager.default.moveItem(at: source, to: URL(fileURLWithPath: location.path + suffix))
            }
        }
        removeUnusedIndexes(in: directory, keeping: location)
        return location
    }

    /// Deletes a vault's index, as when it is removed from the vault list; it is a cache.
    public static func removeIndex(forVault vaultIdentifier: UUID, in cachesDirectory: URL? = nil) {
        guard let caches = cachesDirectory ?? (try? FileManager.default.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: false)) else { return }
        let location = caches.appendingPathComponent("Graphite/Indexes/" + vaultIdentifier.uuidString + ".sqlite")
        for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: location.path + suffix) }
    }

    private static func removeUnusedIndexes(in directory: URL, keeping keptLocation: URL, unusedFor age: TimeInterval = 30 * 86_400) {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey]
        guard let locations = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: Array(keys)) else { return }
        let cutoff = Date.now.addingTimeInterval(-age)
        for databaseLocation in locations where databaseLocation.pathExtension == "sqlite" && databaseLocation.lastPathComponent != keptLocation.lastPathComponent {
            // The journal is written most recently when the index was last used.
            let lastUse = ["", "-wal"].compactMap { suffix in
                try? URL(fileURLWithPath: databaseLocation.path + suffix).resourceValues(forKeys: keys).contentModificationDate
            }.max() ?? .distantPast
            guard lastUse < cutoff else { continue }
            for suffix in ["", "-wal", "-shm"] { try? FileManager.default.removeItem(atPath: databaseLocation.path + suffix) }
        }
    }

    /// A file parsed for the index and ready to be written.
    struct PreparedFile: Sendable {
        let file: IndexedFile
        let semantics: NoteSemantics?
        /// Each frontmatter property's key and its YAML structure encoded as JSON.
        let encodedProperties: [(key: String, encodedNode: String)]
        let propertyLinkTargets: [String]
    }

    /// Parses a file for the index. Static, so a scan runs it outside the actor and queries
    /// are not held up while a batch of notes is parsed.
    static func prepared(_ file: IndexedFile) throws -> PreparedFile {
        // Parsing leaves autoreleased objects behind; releasing them per note keeps a
        // batch of large notes from accumulating them until the batch ends.
        try autoreleasepool {
            let semantics = try file.markdown.map(MarkdownSemantics.parse)
            let properties = semantics?.frontmatter.flatMap(BaseFrontmatter.entries(fromYAML:)) ?? []
            let encoder = JSONEncoder()
            let encodedProperties = try properties.map { entry in (key: entry.key, encodedNode: String(decoding: try encoder.encode(entry.node), as: UTF8.self)) }
            let propertyLinkTargets = BaseFrontmatter.links(in: properties).map { link in Self.storedLinkTarget(link.target, isWiki: link.isWiki, source: file.path) }
            return PreparedFile(file: file, semantics: semantics, encodedProperties: encodedProperties, propertyLinkTargets: propertyLinkTargets)
        }
    }

    public func update(_ files: [IndexedFile], generation: String) throws {
        // Parse outside the transaction. Limit batches at the caller for bounded memory.
        try write(files.map(Self.prepared), generation: generation)
    }

    private func write(_ preparedFiles: [PreparedFile], generation: String) throws {
        guard !preparedFiles.isEmpty else { return }
        try databaseQueue.write { database in
            // Cached statements: every file runs the same few dozen statements, and
            // compiling each one again per file cost more than executing it.
            let fileUpsert = try database.cachedStatement(sql: """
                INSERT INTO files (path, basename, title, size, modified, generation, contentIndexed, created, path_key, name_key, folded_path, folded_name)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(path) DO UPDATE SET basename=excluded.basename, title=excluded.title,
                  size=excluded.size, modified=excluded.modified, generation=excluded.generation,
                  contentIndexed=excluded.contentIndexed, created=excluded.created,
                  path_key=excluded.path_key, name_key=excluded.name_key,
                  folded_path=excluded.folded_path, folded_name=excluded.folded_name
                """)
            // FTS content columns have no ordinary B-tree index. Deleting by
            // path here would turn a full build into a quadratic table scan.
            let searchDeletion = try database.cachedStatement(sql: "DELETE FROM search WHERE rowid = (SELECT rowid FROM files WHERE path = ?)")
            let searchInsertion = try database.cachedStatement(sql: "INSERT INTO search(rowid, path, title, body) SELECT rowid, path, ?, ? FROM files WHERE path = ?")
            let linkDeletion = try database.cachedStatement(sql: "DELETE FROM links WHERE source = ?")
            let perFileDeletions = try Self.perFileTables.map { table in try database.cachedStatement(sql: "DELETE FROM \(table) WHERE path = ?") }
            let propertyInsertion = try database.cachedStatement(sql: "INSERT INTO properties (path, position, key, node) VALUES (?, ?, ?, ?)")
            let propertyLinkInsertion = try database.cachedStatement(sql: "INSERT INTO property_links (path, target, folded_target) VALUES (?, ?, ?)")
            let linkInsertion = try database.cachedStatement(sql: "INSERT INTO links (source, target, isWiki, isEmbed, folded_target) VALUES (?, ?, ?, ?, ?)")
            let aliasInsertion = try database.cachedStatement(sql: "INSERT INTO aliases (alias, path, folded_alias) VALUES (?, ?, ?)")
            let tagInsertion = try database.cachedStatement(sql: "INSERT INTO tags VALUES (?, ?)")
            let headingInsertion = try database.cachedStatement(sql: "INSERT INTO headings VALUES (?, ?)")
            for prepared in preparedFiles {
                let file = prepared.file
                let semantics = prepared.semantics
                let title = semantics?.headings.first ?? file.path.stem
                let contentState: IndexedContentState = semantics != nil ? .indexed : file.isUnreadableAsText ? .unreadableAsText : .notRead
                try fileUpsert.execute(arguments: [file.path.rawValue, file.path.name, title, file.size, file.modified.timeIntervalSince1970, generation, contentState.rawValue,
                                                   (file.created ?? file.modified).timeIntervalSince1970,
                                                   WikiLinkResolver.comparisonKey(file.path.rawValue), WikiLinkResolver.comparisonKey(file.path.name),
                                                   Self.foldedKey(file.path.rawValue), Self.foldedKey(file.path.name)])
                try searchDeletion.execute(arguments: [file.path.rawValue])
                // The whole text, frontmatter included: search finds property values too,
                // and a match's position is its position in the file.
                try searchInsertion.execute(arguments: [title, semantics == nil ? "" : file.markdown ?? "", file.path.rawValue])
                try linkDeletion.execute(arguments: [file.path.rawValue])
                for perFileDeletion in perFileDeletions { try perFileDeletion.execute(arguments: [file.path.rawValue]) }
                for (position, property) in prepared.encodedProperties.enumerated() {
                    try propertyInsertion.execute(arguments: [file.path.rawValue, position, property.key, property.encodedNode])
                }
                for target in Set(prepared.propertyLinkTargets) {
                    try propertyLinkInsertion.execute(arguments: [file.path.rawValue, target, Self.foldedKey(target)])
                }
                if let semantics {
                    for link in semantics.links {
                        let target = Self.storedLinkTarget(link, source: file.path)
                        try linkInsertion.execute(arguments: [file.path.rawValue, target, link.isWiki, link.isEmbed, Self.foldedKey(target)])
                    }
                    for alias in semantics.aliases {
                        try aliasInsertion.execute(arguments: [WikiLinkResolver.comparisonKey(alias), file.path.rawValue, Self.foldedKey(alias)])
                    }
                    for tag in semantics.tags { try tagInsertion.execute(arguments: [tag, file.path.rawValue]) }
                    for heading in semantics.headings { try headingInsertion.execute(arguments: [heading, file.path.rawValue]) }
                }
            }
        }
    }

    // The read-only queries below run outside the actor, straight on the database queue:
    // they do not wait while a scan reads and parses notes, and a cancelled caller
    // interrupts its query instead of letting it run to completion.

    /// Ambiguous results are returned to the caller, never silently selected.
    public nonisolated func resolve(_ target: String, from source: VaultPath, isWiki: Bool = true) async throws -> [VaultPath] {
        try await databaseQueue.read { database in try Self.resolvedPaths(target, from: source, isWiki: isWiki, in: database) }
    }

    static func resolvedPaths(_ target: String, from source: VaultPath, isWiki: Bool, in database: Database) throws -> [VaultPath] {
        for candidate in WikiLinkResolver.directCandidates(target: target, source: source, isWiki: isWiki) {
            // Paths match case-insensitively, through the indexed folded key. Files whose
            // names differ only by case (possible on case-sensitive volumes) prefer the
            // exact spelling, and are otherwise returned together as ambiguous.
            let paths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE folded_path = ? ORDER BY path LIMIT 50",
                                            arguments: [foldedKey(candidate.rawValue)])
            guard !paths.isEmpty else { continue }
            let candidateKey = WikiLinkResolver.comparisonKey(candidate.rawValue)
            if let exactPath = paths.first(where: { path in WikiLinkResolver.comparisonKey(path) == candidateKey }) { return [try VaultPath(exactPath)] }
            return try paths.map(VaultPath.init)
        }
        let part = WikiLinkResolver.comparisonKey(lookupPathPart(of: target, isWiki: isWiki))
        guard !part.isEmpty, !part.contains(":") else { return [] }
        for fileName in WikiLinkResolver.fileNameVariants(for: part) {
            let paths: [String]
            if part.contains("/") {
                // A partial path, such as `[[covers/Book cover.png]]`, names the end of a
                // path, or the whole path when it starts at the vault root (`[[/Folder/Note]]`).
                let pathSuffix = foldedKey(fileName.hasPrefix("/") ? String(fileName.dropFirst()) : fileName)
                paths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE folded_path = ? OR folded_path LIKE ? ESCAPE '\\' ORDER BY path LIMIT 50",
                                            arguments: [pathSuffix, "%/" + escapedForLike(pathSuffix)])
            } else if isWiki {
                paths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE folded_name = ? UNION SELECT path FROM aliases WHERE folded_alias = ? ORDER BY path LIMIT 50",
                                            arguments: [foldedKey(fileName), foldedKey(part)])
            } else {
                // Aliases are Obsidian's Wikilink names; a Markdown link names a file.
                paths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE folded_name = ? ORDER BY path LIMIT 50", arguments: [foldedKey(fileName)])
            }
            if !paths.isEmpty { return try paths.map(VaultPath.init) }
        }
        return []
    }

    /// The path part a link names a file by when no direct path reaches it: as written for
    /// a Wikilink, and percent-decoded for a Markdown link (`My%20Note.md`). Obsidian
    /// resolves a Markdown link in the shortest format (`Note.md`) or as a partial path
    /// by name, as it does a Wikilink.
    static func lookupPathPart(of target: String, isWiki: Bool) -> String {
        let writtenPath = WikiLinkResolver.pathPart(target)
        return isWiki ? writtenPath : (writtenPath.removingPercentEncoding ?? writtenPath)
    }

    /// Number of indexed files in the vault.
    public nonisolated func fileCount() async throws -> Int {
        try await databaseQueue.read { database in try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files") ?? 0 }
    }

    /// Number of indexed files with this file name anywhere in the vault.
    public nonisolated func fileCount(named fileName: String) async throws -> Int {
        try await databaseQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files WHERE folded_name = ?", arguments: [Self.foldedKey(fileName)]) ?? 0
        }
    }

    public nonisolated func outgoingLinks(from source: VaultPath) async throws -> [String] {
        try await databaseQueue.read { database in try String.fetchAll(database, sql: "SELECT DISTINCT target FROM links WHERE source = ? ORDER BY target LIMIT 200", arguments: [source.rawValue]) }
    }

    public nonisolated func backlinks(to destination: VaultPath) async throws -> [VaultPath] {
        try await databaseQueue.read { database in try Self.backlinkSources(to: destination, includesPropertyLinks: false, in: database) }
    }

    /// Every folded link target (`links.folded_target`, `property_links.folded_target`)
    /// that may name `destination`: each trailing part of its path (`Sub/Target.md`,
    /// `Target.md`), with and without the extension, the whole path written from the
    /// vault root (`/Folder/Sub/Target`), and its aliases. A superset: links among the
    /// matching rows must still resolve to `destination`.
    static func foldedLinkTargetCandidates(for destination: VaultPath, in database: Database) throws -> [String] {
        let components = destination.rawValue.split(separator: "/").map(String.init)
        var candidates: [String] = []
        for firstComponentIndex in components.indices {
            let pathSuffix = components[firstComponentIndex...].joined(separator: "/")
            candidates += [pathSuffix, (pathSuffix as NSString).deletingPathExtension]
        }
        candidates += ["/" + destination.rawValue, "/" + (destination.rawValue as NSString).deletingPathExtension]
        candidates += try String.fetchAll(database, sql: "SELECT alias FROM aliases WHERE path = ?", arguments: [destination.rawValue])
        return Array(NSOrderedSet(array: candidates.map(foldedKey)).array.compactMap { candidate in candidate as? String })
    }

    /// - Parameter includesPropertyLinks: Also count links written in frontmatter, as
    ///   Obsidian's `file.backlinks` does in bases.
    static func backlinkSources(to destination: VaultPath, includesPropertyLinks: Bool, in database: Database) throws -> [VaultPath] {
        // Candidate reduction uses the folded target indexes. Every link is then resolved
        // from its note, to respect ambiguity and each kind's rules (`storedLinkTarget`).
        let candidateTargets = try foldedLinkTargetCandidates(for: destination, in: database)
        // A Wikilink relative to its note (`[[../Sub/Target]]`) is kept as written, so it is
        // found by its ending. Targets starting with `.` are a range of the folded index.
        let relativeEndings = Set([destination.name, destination.stem].map(foldedKey)).sorted().map { fileName in "%/" + escapedForLike(fileName) }
        let targetCondition = "folded_target IN (\(databaseQuestionMarks(count: candidateTargets.count)))"
            + " OR (folded_target >= '.' AND folded_target < '/' AND (" + relativeEndings.map { _ in "folded_target LIKE ? ESCAPE '\\'" }.joined(separator: " OR ") + "))"
        let targetArguments = StatementArguments(candidateTargets) + StatementArguments(relativeEndings)
        var sql = "SELECT DISTINCT source, target, isWiki FROM links WHERE \(targetCondition)"
        var arguments = targetArguments
        if includesPropertyLinks {
            // Property links are resolved as Wikilinks, which also find the written path of
            // a Markdown link: beside the note, from the vault root, or by name.
            sql += " UNION SELECT DISTINCT path, target, 1 FROM property_links WHERE \(targetCondition)"
            arguments += targetArguments
        }
        // Every linking row is read: a limit here would drop backlinks without saying so.
        let rows = try Row.fetchAll(database, sql: sql, arguments: arguments)
        var sources: Set<VaultPath> = []
        // A link resolves the same way from every note in one folder, so each written
        // target is resolved once per folder and link kind rather than once per linking note.
        var resolvesToDestination: [String: Bool] = [:]
        let destinationKey = foldedKey(destination.rawValue)
        for row in rows {
            let source = try VaultPath(row["source"] as String)
            guard !sources.contains(source) else { continue }
            let target: String = row["target"]
            let isWiki: Bool = row["isWiki"]
            if foldedKey(target) == destinationKey { sources.insert(source); continue }
            let cacheKey = (isWiki ? "w" : "m") + source.parent.rawValue + "\u{0}" + target
            let isMatch: Bool
            if let cached = resolvesToDestination[cacheKey] {
                isMatch = cached
            } else {
                let resolved = try resolvedPaths(target, from: source, isWiki: isWiki, in: database)
                isMatch = resolved.count == 1 && resolved.first == destination
                resolvesToDestination[cacheKey] = isMatch
            }
            if isMatch { sources.insert(source) }
        }
        return sources.sorted()
    }

    /// The target a link is indexed by, which `resolvedPaths` resolves from the linking note.
    /// Wikilinks keep their written target. Markdown links are percent-decoded: one that
    /// starts with `./` or `../`, or has no path (`#Heading`), can only mean one file, so it
    /// is stored as that vault path; any other may be a path beside the note, from the vault
    /// root or a name (Obsidian's relative, absolute and shortest formats), so it is stored
    /// as written. Each is then among the targets `foldedLinkTargetCandidates` looks up.
    static func storedLinkTarget(_ link: NoteLink, source: VaultPath) -> String {
        storedLinkTarget(link.target, isWiki: link.isWiki, source: source)
    }

    static func storedLinkTarget(_ target: String, isWiki: Bool, source: VaultPath) -> String {
        guard !isWiki else { return WikiLinkResolver.comparisonKey(WikiLinkResolver.pathPart(target)) }
        let writtenPath = WikiLinkResolver.pathPart(target)
        let decodedPath = lookupPathPart(of: target, isWiki: false)
        let isWebOrAppLink = URL(string: writtenPath)?.scheme != nil || URL(string: decodedPath)?.scheme != nil
        guard !isWebOrAppLink else { return WikiLinkResolver.comparisonKey(writtenPath) }
        guard decodedPath.isEmpty || WikiLinkResolver.isExplicitlyRelative(decodedPath),
              let notePath = WikiLinkResolver.directCandidates(target: target, source: source, isWiki: false).first else {
            return WikiLinkResolver.comparisonKey(decodedPath)
        }
        return WikiLinkResolver.comparisonKey(notePath.rawValue)
    }

    /// A file a scan found, with the metadata the unchanged check compares.
    private struct ScannedFile: Sendable {
        let path: VaultPath
        let location: URL
        let size: Int
        let modified: Date
        let created: Date?
        let isMarkdown: Bool
        /// Set once the file is known to have changed: a note whose text the scan reads.
        var readsContent = false
    }

    /// A changed file of a scan batch, read and parsed outside the actor.
    private struct ScanBatchEntry: Sendable {
        let file: IndexedFile
        /// Why the note's text could not be read; the file is still written, without text.
        let readFailure: String?
        let preparation: Result<PreparedFile, any Error>
    }

    /// The text of a note a scan read.
    private enum NoteReading: Sendable {
        case text(String)
        case notText
        case failed(any Error)
    }

    /// What a scan has found and not yet written, and what it reports.
    private struct ScanState {
        var discoveredFiles = 0, updatedFiles = 0, pendingFiles = 0
        var failedPaths: [String] = []
        /// Enumerated files waiting for the unchanged check.
        var scannedFiles: [ScannedFile] = []
        /// Changed files waiting to be read and written.
        var batch: [ScannedFile] = []
        var batchContentBytes = 0
        /// Unchanged files waiting to be marked seen.
        var unchangedPaths: [String] = []

        mutating func recordFailure(_ description: String) {
            if failedPaths.count < 100 { failedPaths.append(description) }
        }
    }

    /// Enumerated files are checked against the index this many at a time, in one read.
    private static let unchangedCheckChunkSize = 256

    public func reconcile(root: URL) async throws -> IndexingReport {
        guard !isScanning else { throw GraphiteError.unavailable("An index scan is already running.") }
        isScanning = true
        let generation = UUID().uuidString
        activeScanGeneration = generation
        defer {
            isScanning = false
            activeScanGeneration = nil
            pathsRefreshedDuringScan.removeAll()
        }
        // The download state is not listed: asking for it makes the file provider inspect
        // every item, which costs more than the rest of the enumeration. It is read only
        // for changed notes, the only files whose content the scan would read.
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey]
        // Set when part of the vault could not be listed. Rows for files there were not
        // marked seen, so pruning would delete files that still exist.
        var isInventoryIncomplete = false
        // Relative URLs: the enumerator may report `/private/var/…` for a root given as
        // `/var/…`, so cutting the root's path length off absolute paths is unreliable.
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants, .producesRelativePathURLs], errorHandler: { _, _ in isInventoryIncomplete = true; return true }) else {
            throw GraphiteError.unavailable("Cannot enumerate the vault.")
        }
        var state = ScanState()
        while let location = enumerator.nextObject() as? URL {
            try Task.checkCancellation()
            let relative = location.relativePath
            let values: URLResourceValues
            do {
                values = try location.resourceValues(forKeys: Set(keys))
            } catch {
                // The item vanished or could not be inspected mid-scan. Its row, if any, is
                // kept rather than pruned on an unknown state; the file presenter or the
                // next scan settles it.
                if let path = try? VaultPath(relative) { state.unchangedPaths.append(path.rawValue) }
                state.recordFailure(relative + ": " + error.localizedDescription)
                continue
            }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true else { continue }
            let path: VaultPath
            do {
                path = try VaultPath(relative)
            } catch {
                // APFS allows names that VaultPath refuses, such as one with a backslash.
                // No row can exist for such a file, so skipping it leaves nothing stale and
                // must not stop deleted files from being pruned.
                state.recordFailure(relative + ": " + error.localizedDescription)
                continue
            }
            state.discoveredFiles += 1
            state.scannedFiles.append(ScannedFile(path: path, location: location, size: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast,
                                                  created: values.creationDate, isMarkdown: DocumentKind(path: path) == .markdown))
            if state.scannedFiles.count >= Self.unchangedCheckChunkSize { try await checkScannedFiles(&state, generation: generation) }
        }
        try await checkScannedFiles(&state, generation: generation)
        try await writeBatch(&state, generation: generation)
        if !isInventoryIncomplete {
            try await databaseQueue.write { database in
                try database.execute(sql: Self.staleSearchRowDeletion, arguments: [generation])
                for table in Self.perFileTables {
                    try database.execute(sql: "DELETE FROM \(table) WHERE path IN (SELECT path FROM files WHERE generation != ?)", arguments: [generation])
                }
                try database.execute(sql: "DELETE FROM links WHERE source IN (SELECT path FROM files WHERE generation != ?)", arguments: [generation])
                try database.execute(sql: "DELETE FROM files WHERE generation != ?", arguments: [generation])
            }
        }
        return IndexingReport(discoveredFiles: state.discoveredFiles, updatedFiles: state.updatedFiles, pendingContentFiles: state.pendingFiles, failedPaths: state.failedPaths)
    }

    /// Checks a chunk of enumerated files against the index in one read, marks unchanged
    /// files seen, and adds changed files to the batch, writing it whenever it is full.
    private func checkScannedFiles(_ state: inout ScanState, generation: String) async throws {
        let storedContentStates = try storedContentStates(of: state.scannedFiles)
        for (var file, storedContentState) in zip(state.scannedFiles, storedContentStates) {
            // A note too large to index or still in the cloud stays unread until its
            // size, date or download state changes; reading it again would give the
            // same result. The download state is asked last, and only when it decides.
            let isContentReadable = (storedContentState == nil || storedContentState == .notRead) && file.isMarkdown
                && file.size <= Self.maximumIndexedNoteBytes && !Self.isNotDownloaded(file.location)
            if let storedContentState, storedContentState != .notRead || !isContentReadable {
                if file.isMarkdown, storedContentState != .indexed { state.pendingFiles += 1 }
                state.unchangedPaths.append(file.path.rawValue)
                continue
            }
            if file.isMarkdown, !isContentReadable { state.pendingFiles += 1 }
            file.readsContent = isContentReadable
            if isContentReadable { state.batchContentBytes += file.size }
            state.batch.append(file)
            state.updatedFiles += 1
            if state.batch.count >= Self.maximumBatchFileCount || state.batchContentBytes >= Self.maximumBatchContentBytes {
                try await writeBatch(&state, generation: generation)
            }
        }
        state.scannedFiles.removeAll(keepingCapacity: true)
        try markSeen(paths: state.unchangedPaths, generation: generation)
        state.unchangedPaths.removeAll(keepingCapacity: true)
        await Task.yield()
    }

    private func writeBatch(_ state: inout ScanState, generation: String) async throws {
        guard !state.batch.isEmpty else { return }
        let entries = await Self.readAndPrepare(state.batch)
        state.batch.removeAll(keepingCapacity: true)
        state.batchContentBytes = 0
        // An unreadable note is still part of the inventory. Its failure must not look
        // like an incomplete scan, or deleted files are never pruned.
        for entry in entries {
            guard let readFailure = entry.readFailure else { continue }
            state.pendingFiles += 1
            state.recordFailure(entry.file.path.rawValue + ": " + readFailure)
        }
        for failure in try writeScanBatch(entries, generation: generation) { state.recordFailure(failure) }
    }

    /// The stored content state of each file whose size and modification date are unchanged,
    /// nil for a changed or new file. One synchronous read for the whole chunk: a separate
    /// asynchronous read per file cost more than the lookup itself.
    private func storedContentStates(of files: [ScannedFile]) throws -> [IndexedContentState?] {
        guard !files.isEmpty else { return [] }
        return try databaseQueue.read { database in
            let lookup = try database.cachedStatement(sql: "SELECT contentIndexed FROM files WHERE path = ? AND size = ? AND modified = ?")
            return try files.map { file in
                try Int.fetchOne(lookup, arguments: [file.path.rawValue, file.size, file.modified.timeIntervalSince1970]).flatMap(IndexedContentState.init(rawValue:))
            }
        }
    }

    /// Whether the file is in the cloud and not downloaded. Reading it would start a download.
    private static func isNotDownloaded(_ location: URL) -> Bool {
        (try? location.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))?.ubiquitousItemDownloadingStatus == .notDownloaded
    }

    /// Reads the notes of a scan batch and parses every file of it. Static, so it runs
    /// outside the actor: queries and saves are not held up while a batch is read and parsed.
    private static func readAndPrepare(_ batch: [ScannedFile]) async -> [ScanBatchEntry] {
        var readings = await readNotes(at: batch.filter(\.readsContent).map(\.location.absoluteURL)).makeIterator()
        return batch.map { scannedFile in
            var markdown: String?
            var isUnreadableAsText = false
            var readFailure: String?
            if scannedFile.readsContent, let reading = readings.next() {
                switch reading {
                case .text(let text): markdown = text
                case .notText:
                    isUnreadableAsText = true
                    readFailure = GraphiteError.invalidFile("Note is not UTF-8.").localizedDescription
                case .failed(let error): readFailure = error.localizedDescription
                }
            }
            let file = IndexedFile(path: scannedFile.path, size: scannedFile.size, modified: scannedFile.modified, created: scannedFile.created,
                                   markdown: markdown, isUnreadableAsText: isUnreadableAsText)
            return ScanBatchEntry(file: file, readFailure: readFailure, preparation: Result { try prepared(file) })
        }
    }

    /// Reads notes under one file coordination for all of them: coordinating each file
    /// separately cost ten times more than reading it. When the coordination as a whole
    /// fails, each note is read under its own, so one file's failure costs only that file.
    private static func readNotes(at locations: [URL]) async -> [NoteReading] {
        guard !locations.isEmpty else { return [] }
        let intents = locations.map { location in NSFileAccessIntent.readingIntent(with: location, options: []) }
        let queue = OperationQueue()
        queue.qualityOfService = .utility
        let coordinatedReadings: [NoteReading]? = await withCheckedContinuation { continuation in
            NSFileCoordinator(filePresenter: nil).coordinate(with: intents, queue: queue) { coordinationError in
                guard coordinationError == nil else { continuation.resume(returning: nil); return }
                // Each note is read through its intent's URL, which follows a move
                // reported during coordination.
                continuation.resume(returning: intents.map { intent in noteReading(from: Result { try readNoteData(at: intent.url) }) })
            }
        }
        if let coordinatedReadings { return coordinatedReadings }
        let writer = AtomicFileWriter()
        return locations.map { location in noteReading(from: Result { try writer.read(location, maximumBytes: maximumIndexedNoteBytes).data }) }
    }

    /// The same size check and read as `AtomicFileWriter.read`, for a location that is
    /// already coordinated.
    private static func readNoteData(at location: URL) throws -> Data {
        let size = try location.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= maximumIndexedNoteBytes else { throw GraphiteError.oversized("This file exceeds the current editor's memory budget.") }
        return try Data(contentsOf: location)
    }

    private static func noteReading(from dataResult: Result<Data, any Error>) -> NoteReading {
        switch dataResult {
        case .success(let data): String(data: data, encoding: .utf8).map(NoteReading.text) ?? .notText
        case .failure(let error): .failed(error)
        }
    }

    /// Writes one batch of a scan and returns a description of each file it could not
    /// write. After a failed batch write each file is tried alone, so one bad file costs
    /// only itself and the batch never has to be kept for another attempt. Files that
    /// still fail, or could not be parsed, keep their existing rows, marked seen, so the
    /// prune does not remove files that exist; the next scan tries them again.
    private func writeScanBatch(_ entries: [ScanBatchEntry], generation: String) throws -> [String] {
        var failures: [String] = []
        var failedPaths: [String] = []
        var preparedFiles: [PreparedFile] = []
        for entry in entries where !isSupersededByRefresh(entry.file) {
            switch entry.preparation {
            case .success(let prepared): preparedFiles.append(prepared)
            case .failure(let error):
                failures.append(entry.file.path.rawValue + ": " + error.localizedDescription)
                failedPaths.append(entry.file.path.rawValue)
            }
        }
        do {
            try write(preparedFiles, generation: generation)
        } catch {
            for prepared in preparedFiles {
                do {
                    try write([prepared], generation: generation)
                } catch {
                    failures.append(prepared.file.path.rawValue + ": " + error.localizedDescription)
                    failedPaths.append(prepared.file.path.rawValue)
                }
            }
        }
        try markSeen(paths: failedPaths, generation: generation)
        return failures
    }

    /// Whether `refresh` wrote or removed this file after the scan read it, directly or by
    /// removing a folder that contains it.
    private func isSupersededByRefresh(_ file: IndexedFile) -> Bool {
        guard !pathsRefreshedDuringScan.isEmpty else { return false }
        if let refreshedModification = pathsRefreshedDuringScan[file.path.rawValue] { return refreshedModification >= file.modified }
        var ancestor = file.path.parent
        while !ancestor.rawValue.isEmpty {
            if pathsRefreshedDuringScan[ancestor.rawValue] == .distantFuture { return true }
            ancestor = ancestor.parent
        }
        return false
    }

    /// Re-reads specific files after Graphite saves them or a file presenter reports a
    /// change. Missing files are removed, with everything inside them when they were
    /// folders. This avoids a whole-vault scan per edit.
    ///
    /// Only files a scan would index are kept: hidden items (`.trash`, `.obsidian`) and
    /// items reached through a symbolic link are removed like missing ones. A note that
    /// cannot be read stays in the inventory without searchable text, as in a scan, and
    /// does not stop the other paths from being refreshed.
    public func refresh(paths: [VaultPath], root: URL) throws {
        let writer = AtomicFileWriter()
        let generation = activeScanGeneration ?? UUID().uuidString
        var changedFiles: [IndexedFile] = []
        var changedContentBytes = 0
        var removedPaths: [String] = []
        func writeChangedFiles() throws {
            try update(changedFiles, generation: generation)
            if activeScanGeneration != nil {
                for file in changedFiles { pathsRefreshedDuringScan[file.path.rawValue] = file.modified }
            }
            changedFiles.removeAll(keepingCapacity: true)
            changedContentBytes = 0
        }
        for path in Set(paths) {
            // Hidden files, such as Obsidian's settings, are not notes: a scan skips them, and
            // a change reported for one leaves it out of the index too.
            guard !path.isHidden else {
                removedPaths.append(path.rawValue)
                continue
            }
            guard let file = refreshedFile(at: path, root: root, writer: writer) else {
                if !isExistingIndexableDirectory(path, root: root) { removedPaths.append(path.rawValue) }
                continue
            }
            changedFiles.append(file)
            changedContentBytes += file.markdown?.utf8.count ?? 0
            if changedFiles.count >= Self.maximumBatchFileCount || changedContentBytes >= Self.maximumBatchContentBytes { try writeChangedFiles() }
        }
        try writeChangedFiles()
        guard !removedPaths.isEmpty else { return }
        if activeScanGeneration != nil {
            for removedPath in removedPaths { pathsRefreshedDuringScan[removedPath] = .distantFuture }
        }
        try databaseQueue.write { database in
            let searchDeletion = try database.cachedStatement(sql: "DELETE FROM search WHERE rowid = (SELECT rowid FROM files WHERE path = ?)")
            let perFileDeletions = try Self.perFileTables.map { table in try database.cachedStatement(sql: "DELETE FROM \(table) WHERE path = ?") }
            let linkDeletion = try database.cachedStatement(sql: "DELETE FROM links WHERE source = ?")
            let fileDeletion = try database.cachedStatement(sql: "DELETE FROM files WHERE path = ?")
            for removedPath in removedPaths {
                // '0' follows '/' in code-unit order, so this range is exactly the paths
                // inside a removed folder, found through the primary key.
                let descendantPaths = try String.fetchAll(database, sql: "SELECT path FROM files WHERE path > ? AND path < ?", arguments: [removedPath + "/", removedPath + "0"])
                for path in [removedPath] + descendantPaths {
                    try searchDeletion.execute(arguments: [path])
                    for perFileDeletion in perFileDeletions { try perFileDeletion.execute(arguments: [path]) }
                    try linkDeletion.execute(arguments: [path])
                    try fileDeletion.execute(arguments: [path])
                }
            }
        }
    }

    /// The file at `path` as a scan would index it, or nil when a scan would not index it:
    /// missing, not a regular file, hidden, or reached through a symbolic link.
    private func refreshedFile(at path: VaultPath, root: URL, writer: AtomicFileWriter) -> IndexedFile? {
        guard !path.isHidden, let location = Self.locationWithoutSymbolicLinks(of: path, root: root),
              let values = try? location.resourceValues(forKeys: [.isRegularFileKey, .isHiddenKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey, .ubiquitousItemDownloadingStatusKey]),
              values.isRegularFile == true, values.isHidden != true else { return nil }
        let size = values.fileSize ?? 0
        var markdown: String?
        var isUnreadableAsText = false
        if DocumentKind(path: path) == .markdown, values.ubiquitousItemDownloadingStatus != .notDownloaded, size <= Self.maximumIndexedNoteBytes {
            // `try?`: a note that cannot be read right now (removed mid-refresh, no
            // permission, grown past the limit) keeps its inventory row without text, and
            // the next scan reads it again.
            if let snapshot = try? writer.read(location, maximumBytes: Self.maximumIndexedNoteBytes) {
                markdown = String(data: snapshot.data, encoding: .utf8)
                isUnreadableAsText = markdown == nil
            }
        }
        return IndexedFile(path: path, size: size, modified: values.contentModificationDate ?? .distantPast, created: values.creationDate,
                           markdown: markdown, isUnreadableAsText: isUnreadableAsText)
    }

    /// Whether `path` is a folder a scan would enter. Its files are refreshed on their
    /// own or by a scan, so refreshing the folder itself changes nothing.
    private func isExistingIndexableDirectory(_ path: VaultPath, root: URL) -> Bool {
        guard !path.isHidden, let location = Self.locationWithoutSymbolicLinks(of: path, root: root),
              let values = try? location.resourceValues(forKeys: [.isDirectoryKey, .isHiddenKey]) else { return false }
        return values.isDirectory == true && values.isHidden != true
    }

    /// The location of `path`, or nil when reaching it follows a symbolic link inside the
    /// vault, which a scan does not do.
    private static func locationWithoutSymbolicLinks(of path: VaultPath, root: URL) -> URL? {
        guard let location = try? path.url(in: root) else { return nil }
        let unresolvedLocation = root.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(path.rawValue).standardizedFileURL
        return location.path == unresolvedLocation.path ? location : nil
    }

    /// Deletes every cached row so the next scan rebuilds the index from the vault.
    public func removeAllEntries() throws {
        try databaseQueue.write { database in
            for table in ["search", "links", "files"] + Self.perFileTables { try database.execute(sql: "DELETE FROM \(table)") }
        }
    }

    private func markSeen(paths: [String], generation: String) throws {
        guard !paths.isEmpty else { return }
        try databaseQueue.write { database in
            let generationUpdate = try database.cachedStatement(sql: "UPDATE files SET generation = ? WHERE path = ?")
            for path in paths { try generationUpdate.execute(arguments: [generation, path]) }
        }
    }
}

