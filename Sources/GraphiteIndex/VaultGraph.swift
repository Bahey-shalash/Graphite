import Foundation
import GRDB
import GraphiteCore

extension VaultIndex {
    /// Every file, the links between them (in note text and in properties, embeds
    /// included), links to files that do not exist, and each file's tags, for the graph view.
    /// Links resolve as they do everywhere else; a link that could mean several files is
    /// left out rather than drawn to one of them.
    public func linkGraph() throws -> LinkGraph {
        try databaseQueue.read { database in
            let resolver = try GraphLinkResolver(database: database)
            let files = resolver.paths.compactMap { path in try? VaultPath(path) }
            let rows = try Row.fetchAll(database, sql: "SELECT source, target, isWiki FROM links UNION SELECT path, target, 1 FROM property_links")
            var resolvedByKey: [String: [String]] = [:]
            var links: [(source: VaultPath, target: VaultPath)] = []
            var unresolvedLinks: [(source: VaultPath, target: String)] = []
            for row in rows {
                guard let source = try? VaultPath(row["source"] as String) else { continue }
                let target: String = row["target"]
                let isWiki: Bool = row["isWiki"]
                // Web pages and other apps' links are not notes.
                guard !target.isEmpty, !Self.isExternalLink(target) else { continue }
                // A link resolves the same way from every note in one folder.
                let cacheKey = (isWiki ? "w" : "m") + source.parent.rawValue + "\u{0}" + target
                let resolved: [String]
                if let cached = resolvedByKey[cacheKey] {
                    resolved = cached
                } else {
                    resolved = resolver.resolve(target, from: source, isWiki: isWiki)
                    resolvedByKey[cacheKey] = resolved
                }
                if resolved.count == 1, let destination = resolved.first.flatMap({ path in try? VaultPath(path) }) {
                    links.append((source, destination))
                } else if resolved.isEmpty {
                    unresolvedLinks.append((source, target))
                }
            }
            let tags = try Row.fetchAll(database, sql: "SELECT path, tag FROM tags").compactMap { row -> (path: VaultPath, tag: String)? in
                guard let path = try? VaultPath(row["path"] as String) else { return nil }
                return (path, row["tag"])
            }
            return LinkGraph.build(files: files, links: links, unresolvedLinks: unresolvedLinks, tags: tags)
        }
    }

    /// The resolver the graph uses, for tests that compare it with `resolve`.
    func graphLinkResolver() throws -> GraphLinkResolver {
        try databaseQueue.read { database in try GraphLinkResolver(database: database) }
    }

    static func isExternalLink(_ target: String) -> Bool {
        guard let colon = target.firstIndex(of: ":") else { return false }
        let scheme = target[..<colon]
        // `C:` alone is not a scheme worth treating as one, and schemes have no spaces.
        return scheme.count > 1 && scheme.allSatisfy { character in character.isLetter || character.isNumber || "+-.".contains(character) }
    }
}

/// `VaultIndex.resolvedPaths` over names held in memory: the graph resolves every link in
/// the vault, and a query per link takes seconds for a large vault. Names compare by the
/// folded keys the index stores (`VaultIndex.foldedKey`), ignoring case for every letter.
struct GraphLinkResolver {
    /// Every file, sorted as SQLite sorts them.
    let paths: [String]
    private let pathsByFoldedPath: [String: [String]]
    private let pathsByFoldedName: [String: [String]]
    /// Files by the last component of their folded path, which a partial path's folded
    /// suffix shares with every path it matches.
    private let pathsByFoldedLastComponent: [String: [String]]
    private let pathsByFoldedAlias: [String: [String]]
    private let foldedPathsByPath: [String: String]

    init(database: Database) throws {
        var paths: [String] = []
        var pathsByFoldedPath: [String: [String]] = [:]
        var pathsByFoldedName: [String: [String]] = [:]
        var pathsByFoldedLastComponent: [String: [String]] = [:]
        var foldedPathsByPath: [String: String] = [:]
        for row in try Row.fetchAll(database, sql: "SELECT path, folded_path, folded_name FROM files ORDER BY path") {
            let path: String = row["path"]
            let foldedPath = (row["folded_path"] as String?) ?? VaultIndex.foldedKey(path)
            let foldedName = (row["folded_name"] as String?) ?? VaultIndex.foldedKey((path as NSString).lastPathComponent)
            paths.append(path)
            foldedPathsByPath[path] = foldedPath
            pathsByFoldedPath[foldedPath, default: []].append(path)
            pathsByFoldedName[foldedName, default: []].append(path)
            pathsByFoldedLastComponent[Self.lastComponent(of: foldedPath), default: []].append(path)
        }
        var pathsByFoldedAlias: [String: [String]] = [:]
        for row in try Row.fetchAll(database, sql: "SELECT alias, folded_alias, path FROM aliases") {
            let foldedAlias = (row["folded_alias"] as String?) ?? VaultIndex.foldedKey(row["alias"] as String)
            pathsByFoldedAlias[foldedAlias, default: []].append(row["path"])
        }
        self.paths = paths
        self.pathsByFoldedPath = pathsByFoldedPath
        self.pathsByFoldedName = pathsByFoldedName
        self.pathsByFoldedLastComponent = pathsByFoldedLastComponent
        self.pathsByFoldedAlias = pathsByFoldedAlias
        self.foldedPathsByPath = foldedPathsByPath
    }

    func resolve(_ target: String, from source: VaultPath, isWiki: Bool) -> [String] {
        for candidate in WikiLinkResolver.directCandidates(target: target, source: source, isWiki: isWiki) {
            // Files whose names differ only by case prefer the exact spelling, and are
            // otherwise returned together as ambiguous.
            let matches = Array((pathsByFoldedPath[VaultIndex.foldedKey(candidate.rawValue)] ?? []).prefix(50))
            guard !matches.isEmpty else { continue }
            let candidateKey = WikiLinkResolver.comparisonKey(candidate.rawValue)
            if let exactPath = matches.first(where: { path in WikiLinkResolver.comparisonKey(path) == candidateKey }) { return [exactPath] }
            return matches
        }
        let part = WikiLinkResolver.comparisonKey(VaultIndex.lookupPathPart(of: target, isWiki: isWiki))
        guard !part.isEmpty, !part.contains(":") else { return [] }
        for fileName in WikiLinkResolver.fileNameVariants(for: part) {
            var matches: Set<String> = []
            if part.contains("/") {
                // A partial path, such as `[[covers/Book cover.png]]`, names the end of a
                // path, or the whole path when it starts at the vault root (`[[/Folder/Note]]`).
                let pathSuffix = VaultIndex.foldedKey(fileName.hasPrefix("/") ? String(fileName.dropFirst()) : fileName)
                for path in pathsByFoldedLastComponent[Self.lastComponent(of: pathSuffix)] ?? [] {
                    guard let foldedPath = foldedPathsByPath[path] else { continue }
                    if foldedPath == pathSuffix || foldedPath.hasSuffix("/" + pathSuffix) { matches.insert(path) }
                }
            } else {
                matches.formUnion(pathsByFoldedName[VaultIndex.foldedKey(fileName)] ?? [])
                if isWiki { matches.formUnion(pathsByFoldedAlias[VaultIndex.foldedKey(part)] ?? []) }
            }
            if !matches.isEmpty { return Array(matches.sorted().prefix(50)) }
        }
        return []
    }

    private static func lastComponent(of foldedPath: String) -> String {
        foldedPath.split(separator: "/", omittingEmptySubsequences: false).last.map(String.init) ?? foldedPath
    }
}
