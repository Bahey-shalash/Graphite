import Foundation
import GRDB
import GraphiteCore

/// A note whose links change because files moved.
public struct LinkUpdate: Sendable {
    /// The note's path after the move.
    public let path: VaultPath
    /// The revision the note had when the update was planned; a note changed since then is left alone.
    public let revision: FileRevision
    /// The whole new text, including a leading byte order mark when the note had one.
    public let updatedText: String
    public let changedLinkCount: Int
}

/// Why a note's links were left as they were.
public enum LinkUpdateFailure: Sendable, Equatable {
    /// The note changed after the update was planned.
    case changedSincePlanning
    /// The note is larger than Graphite rewrites.
    case tooLarge
    /// The note is not UTF-8 text.
    case notText
    /// The note could not be read, for example because its file provider refused. The
    /// associated text describes the cause.
    case unreadable(String)
    /// The note's links could not be located reliably in its text, so rewriting it
    /// could have damaged it.
    case linksNotLocated
    /// Writing the note failed, for example because its folder is read-only or the
    /// disk is full. The associated text describes the cause.
    case saveFailed(String)
    /// A link in the note reaches a moved file but could not be rewritten, so the note
    /// was left unchanged rather than updated with that link broken.
    case linkNotRewritable

    /// The cause in plain words, for the message that lists the notes.
    public var explanation: String {
        switch self {
        case .changedSincePlanning: "it changed elsewhere in the meantime"
        case .tooLarge: "it is too large to update"
        case .notText: "it is not UTF-8 text"
        case .unreadable(let cause): "it could not be read: \(cause)"
        case .linksNotLocated: "its links could not be located safely"
        case .saveFailed(let cause): "it could not be saved: \(cause)"
        case .linkNotRewritable: "one of its links could not be rewritten"
        }
    }
}

/// What moving or renaming a file or folder does to links, worked out before anything moves.
public struct LinkUpdatePlan: Sendable {
    /// Every moved file, from its old path to its new one.
    public let moves: [VaultPath: VaultPath]
    public let updates: [LinkUpdate]
    /// Linking notes that planning could not rewrite, by their path after the move.
    /// They are reported as not updated when the plan is applied.
    public let notesNotUpdated: [VaultPath: LinkUpdateFailure]
    public var changedLinkCount: Int { updates.reduce(0) { count, update in count + update.changedLinkCount } }
}

public struct MoveReport: Sendable {
    public let newPath: VaultPath
    /// Every moved file, from its old path to its new one, also when links were not updated.
    public let moves: [VaultPath: VaultPath]
    public let updatedNotes: [VaultPath]
    /// Notes whose links were not updated, with the reason for each.
    public let failures: [VaultPath: LinkUpdateFailure]
    /// Notes whose links were not updated, in path order.
    public var notesNotUpdated: [VaultPath] { failures.keys.sorted() }
}

/// Moves and renames that keep links working, as Obsidian's "Automatically update
/// internal links" does. Links are found through the index and rewritten in the style
/// they were written in; every note write is revision-checked.
public struct VaultFileOperations: Sendable {
    public let store: VaultStore
    public let index: VaultIndex
    /// Notes larger than this are not rewritten; they are listed as not updated.
    static let maximumRewrittenNoteBytes = 8 * 1_048_576
    private static let byteOrderMark = Data([0xEF, 0xBB, 0xBF])

    public init(store: VaultStore, index: VaultIndex) {
        self.store = store; self.index = index
    }

    /// The link changes that moving `path` (a file or a folder) to `destination` needs.
    public func linkUpdates(forMoving path: VaultPath, to destination: VaultPath) async throws -> LinkUpdatePlan {
        let moves = try await movedFiles(forMoving: path, to: destination)
        var sources = Set<VaultPath>()
        for movedPath in moves.keys { sources.formUnion(try await index.linkingNotes(to: movedPath)) }
        // A moved note's own relative links point somewhere else from its new folder.
        for movedPath in moves.keys where DocumentKind(path: movedPath) == .markdown { sources.insert(movedPath) }
        // Only a file whose own name changes alters how many files share a name: files
        // carried along by a folder move keep theirs.
        let renamedFiles = moves.filter { previousPath, newPath in previousPath.name != newPath.name }
        let canonicalRootPath = try? store.root.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath
        var nameCounts: [String: Int] = [:]
        var updates: [LinkUpdate] = []
        var notesNotUpdated: [VaultPath: LinkUpdateFailure] = [:]
        for source in sources.sorted() where DocumentKind(path: source) == .markdown {
            let newSource = moves[source] ?? source
            let snapshot: FileSnapshot
            do {
                snapshot = try await store.read(source, maximumBytes: Self.maximumRewrittenNoteBytes)
            } catch GraphiteError.oversized {
                notesNotUpdated[newSource] = .tooLarge
                continue
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                // The index still lists a note that is gone; it has no links to update.
                continue
            } catch {
                notesNotUpdated[newSource] = .unreadable(error.localizedDescription)
                continue
            }
            guard let text = String(data: snapshot.data, encoding: .utf8) else {
                notesNotUpdated[newSource] = .notText
                continue
            }
            let links = try NoteLinkScanner.links(in: text)
            let noteText = text as NSString
            // A link whose range does not hold that link means the scan misread the note's
            // layout, and other links may be missing too; nothing in it is rewritten.
            guard links.allSatisfy({ link in Self.rangeHoldsLink(link, in: noteText) }) else {
                notesNotUpdated[newSource] = .linksNotLocated
                continue
            }
            var replacements: [(range: NSRange, text: String)] = []
            var hasLinkNotRewritable = false
            for link in links {
                let writtenPath = LinkRewriter.writtenPath(of: link)
                guard !writtenPath.isEmpty, URL(string: writtenPath)?.scheme == nil,
                      let previousTarget = try await resolvedTarget(of: link, from: source, canonicalRootPath: canonicalRootPath) else { continue }
                let target = moves[previousTarget] ?? previousTarget
                guard target != previousTarget || newSource != source else { continue }
                let isNameUnique = try await nameCount(of: target.name, renamedFiles: renamedFiles, cache: &nameCounts) == 1
                let newPathPart = LinkRewriter.pathPart(linkingTo: target, from: newSource, writtenPath: writtenPath, isWiki: link.isWiki,
                                                        previousTarget: previousTarget, previousSource: source, isNameUnique: isNameUnique)
                guard newPathPart != writtenPath else { continue }
                let linkText = noteText.substring(with: link.range)
                // A reference-style link (`[text][ref]`) holds no destination, and an image in
                // its label must not be replaced: `replacingPath` returns nil for it. Its
                // definition (`[ref]: Note.md`) is scanned as a link of its own and rewritten.
                // Any other link it cannot rewrite would break silently.
                guard let replacement = LinkRewriter.replacingPath(inLinkText: linkText, isWiki: link.isWiki, newPathPart: newPathPart) else {
                    if link.isWiki || !Self.isReferenceStyleLink(linkText) { hasLinkNotRewritable = true }
                    continue
                }
                guard replacement != linkText else { continue }
                replacements.append((link.range, replacement))
            }
            if hasLinkNotRewritable {
                notesNotUpdated[newSource] = .linkNotRewritable
                continue
            }
            guard !replacements.isEmpty else { continue }
            // Decoding drops a UTF-8 byte order mark; it is written back so the rest of the
            // file keeps its bytes (a Windows editor may rely on it).
            let hasDroppedByteOrderMark = snapshot.data.starts(with: Self.byteOrderMark) && !text.hasPrefix("\u{FEFF}")
            let updatedText = (hasDroppedByteOrderMark ? "\u{FEFF}" : "") + LinkRewriter.applying(replacements, to: text)
            updates.append(LinkUpdate(path: newSource, revision: snapshot.revision, updatedText: updatedText, changedLinkCount: replacements.count))
        }
        return LinkUpdatePlan(moves: moves, updates: updates, notesNotUpdated: notesNotUpdated)
    }

    /// Moves `path` to `destination`, then writes the planned link updates.
    ///
    /// - Parameter plan: The planned updates, or nil to move without changing links.
    ///   The report lists every moved file either way, so the index can follow them.
    public func move(_ path: VaultPath, to destination: VaultPath, applying plan: LinkUpdatePlan?) async throws -> MoveReport {
        let moves: [VaultPath: VaultPath]
        if let plan { moves = plan.moves } else { moves = try await movedFiles(forMoving: path, to: destination) }
        try await store.move(path, to: destination)
        var updatedNotes: [VaultPath] = []
        var failures = plan?.notesNotUpdated ?? [:]
        for update in plan?.updates ?? [] {
            do {
                _ = try await store.save(Data(update.updatedText.utf8), at: update.path, expecting: .revision(update.revision))
                updatedNotes.append(update.path)
            } catch GraphiteError.conflict {
                failures[update.path] = .changedSincePlanning
            } catch {
                failures[update.path] = .saveFailed(error.localizedDescription)
            }
        }
        return MoveReport(newPath: destination, moves: moves, updatedNotes: updatedNotes, failures: failures)
    }

    /// Every file that moving `path` moves, from its old path to its new one. A folder's
    /// files are listed from the file system as well as the index: before the first scan
    /// finishes, or after files were added since, the index alone would miss some.
    private func movedFiles(forMoving path: VaultPath, to destination: VaultPath) async throws -> [VaultPath: VaultPath] {
        let location = try path.url(in: store.root)
        let isFolder = (try? location.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        guard isFolder else { return [path: destination] }
        // Indexed paths that are gone from the disk stay in the list, so refreshing the
        // index with the report removes their rows.
        var files = Set(try await index.paths(inside: path))
        files.formUnion(Self.regularFiles(inside: path, at: location))
        var moves: [VaultPath: VaultPath] = [:]
        for file in files { moves[file] = try file.replacingPrefix(path, with: destination) }
        return moves
    }

    /// Regular files under `folder` on disk, skipping hidden items, package contents and
    /// symbolic links as the index scan does. Items that cannot be listed are left to the
    /// index's list.
    private static func regularFiles(inside folder: VaultPath, at location: URL) -> [VaultPath] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: location, includingPropertiesForKeys: keys,
                                                              options: [.skipsHiddenFiles, .skipsPackageDescendants, .producesRelativePathURLs]) else { return [] }
        var files: [VaultPath] = []
        while let fileLocation = enumerator.nextObject() as? URL {
            guard let values = try? fileLocation.resourceValues(forKeys: Set(keys)) else { continue }
            if values.isSymbolicLink == true { enumerator.skipDescendants(); continue }
            guard values.isRegularFile == true, let file = try? folder.appending(fileLocation.relativePath) else { continue }
            files.append(file)
        }
        return files
    }

    /// Whether `link.range` lies inside the text and holds a link of the scanned kind.
    /// A Markdown link written inline, or a link reference definition (`[ref]: Note.md`),
    /// must also contain its destination, unless the destination is empty (`[text]()`) or
    /// the text has a backslash escape or character reference, which the parser decodes.
    ///
    /// The scanner reports a frontmatter link that is the only link in a quoted YAML value
    /// with its quotes (`'[[Note]]'`), and reads its target without YAML's escapes, so
    /// inside quotes only the link's brackets are checked.
    private static func rangeHoldsLink(_ link: NoteLink, in text: NSString) -> Bool {
        guard link.location >= 0, link.length > 0, NSMaxRange(link.range) <= text.length else { return false }
        let linkText = text.substring(with: link.range)
        if isEnclosedInYAMLQuotes(linkText) {
            return link.isWiki ? linkText.contains("[[") && linkText.contains("]]") : linkText.contains("](")
        }
        if link.isWiki { return (linkText.hasPrefix("[[") || linkText.hasPrefix("![[")) && linkText.hasSuffix("]]") }
        // Links with a scheme, such as autolinks, are never rewritten.
        if URL(string: WikiLinkResolver.pathPart(link.target))?.scheme != nil { return true }
        guard linkText.hasPrefix("[") || linkText.hasPrefix("![") else { return false }
        // Reference links (`[text][label]`) hold their destination elsewhere.
        if linkText.hasSuffix("]") { return true }
        let mayDecodeDestination = linkText.contains("\\") || linkText.contains("&")
        let holdsDestination = link.target.isEmpty || mayDecodeDestination || linkText.contains(link.target)
        let isReferenceDefinition = linkText.contains("]:")
        return (linkText.hasSuffix(")") || isReferenceDefinition) && holdsDestination
    }

    /// A Markdown link written `[text][ref]`, `[text][]` or `[text]`, whose destination is
    /// in a separate definition.
    private static func isReferenceStyleLink(_ linkText: String) -> Bool {
        linkText.hasSuffix("]")
    }

    /// Whether `linkText` starts and ends with the same YAML quote character.
    private static func isEnclosedInYAMLQuotes(_ linkText: String) -> Bool {
        guard linkText.count >= 2, let first = linkText.first, first == "'" || first == "\"" else { return false }
        return linkText.last == first
    }

    /// The file a link reaches before anything moves, if exactly one.
    private func resolvedTarget(of link: NoteLink, from source: VaultPath, canonicalRootPath: String?) async throws -> VaultPath? {
        for candidate in WikiLinkResolver.directCandidates(target: link.target, source: source, isWiki: link.isWiki) {
            if try await store.fileExists(candidate) { return storedSpelling(of: candidate, canonicalRootPath: canonicalRootPath) }
        }
        let matches = try await index.resolve(link.target, from: source, isWiki: link.isWiki)
        return matches.count == 1 ? matches.first : nil
    }

    /// `candidate` spelled as the file system stores it. A case-insensitive volume (the
    /// default on macOS and many file providers) finds `notes/old name.md` for the file
    /// `Notes/Old name.md`, but the moved paths use the stored spelling. When the stored
    /// spelling cannot be read, or differs by more than letter case and Unicode
    /// composition (a symbolic link on the way), the candidate is kept.
    private func storedSpelling(of candidate: VaultPath, canonicalRootPath: String?) -> VaultPath {
        guard let canonicalRootPath,
              let canonicalPath = try? candidate.url(in: store.root).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath,
              canonicalPath.hasPrefix(canonicalRootPath + "/"),
              let storedPath = try? VaultPath(String(canonicalPath.dropFirst(canonicalRootPath.count + 1))),
              storedPath.rawValue.lowercased() == candidate.rawValue.lowercased() else { return candidate }
        return storedPath
    }

    /// How many files will have this name once the moves are done.
    ///
    /// The renamed files are excluded from the index's count by their exact paths and
    /// added back under their new names, so the result does not depend on whether the
    /// index folds the case of letters beyond ASCII.
    private func nameCount(of name: String, renamedFiles: [VaultPath: VaultPath], cache: inout [String: Int]) async throws -> Int {
        let key = WikiLinkResolver.comparisonKey(name)
        if let cached = cache[key] { return cached }
        let foldedKey = key.lowercased()
        var count = try await index.fileCount(named: name, excluding: Array(renamedFiles.keys))
        for newPath in renamedFiles.values where WikiLinkResolver.comparisonKey(newPath.name).lowercased() == foldedKey { count += 1 }
        cache[key] = count
        return count
    }
}

extension VaultIndex {
    /// Every indexed file inside `folder`, at any depth; every file for the vault root.
    public func paths(inside folder: VaultPath) throws -> [VaultPath] {
        guard !folder.rawValue.isEmpty else {
            return try databaseQueue.read { database in try String.fetchAll(database, sql: "SELECT path FROM files").map(VaultPath.init) }
        }
        let prefix = folder.rawValue + "/"
        return try databaseQueue.read { database in
            // An exact prefix (SQLite counts characters as Unicode scalars): LIKE would ignore
            // case and match another folder on a case-sensitive volume.
            try String.fetchAll(database, sql: "SELECT path FROM files WHERE substr(path, 1, ?) = ?", arguments: [prefix.unicodeScalars.count, prefix])
                .map(VaultPath.init)
        }
    }

    /// Notes with a link, in their text or properties, that reaches `destination`.
    public func linkingNotes(to destination: VaultPath) throws -> [VaultPath] {
        try databaseQueue.read { database in try Self.backlinkSources(to: destination, includesPropertyLinks: true, in: database) }
    }

    /// Number of indexed files with this file name, not counting `excludedPaths`. Names
    /// compare as `fileCount(named:)` and the Wikilink resolver compare them.
    func fileCount(named fileName: String, excluding excludedPaths: [VaultPath]) throws -> Int {
        let exclusion = excludedPaths.isEmpty ? "" : " AND path NOT IN (" + Array(repeating: "?", count: excludedPaths.count).joined(separator: ",") + ")"
        return try databaseQueue.read { database in
            try Int.fetchOne(database, sql: "SELECT COUNT(*) FROM files WHERE name_key = ? COLLATE NOCASE" + exclusion,
                             arguments: StatementArguments([WikiLinkResolver.comparisonKey(fileName)] + excludedPaths.map(\.rawValue))) ?? 0
        }
    }
}
