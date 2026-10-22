import Foundation

/// A note, attachment, tag or link target without a file, as Obsidian's graph view shows it.
public struct GraphNode: Hashable, Sendable, Identifiable {
    public enum Kind: Hashable, Sendable {
        case note, attachment, tag
        /// A link to a file that does not exist.
        case unresolved
    }

    /// The vault path, `#tag` for a tag, or the written link target for an unresolved link.
    public let id: String
    public let kind: Kind

    public init(id: String, kind: Kind) {
        self.id = id
        self.kind = kind
    }

    public static func file(_ path: VaultPath) -> GraphNode {
        GraphNode(id: path.rawValue, kind: DocumentKind(path: path) == .markdown ? .note : .attachment)
    }

    public var path: VaultPath? {
        kind == .note || kind == .attachment ? try? VaultPath(id) : nil
    }

    /// The name shown beside the node: a note without `.md`, a file with its extension.
    public var title: String {
        switch kind {
        case .note: path?.stem ?? id
        case .attachment: path?.name ?? id
        case .tag, .unresolved: id
        }
    }
}

/// A link between two nodes, by their identifiers. A graph keeps at most one per pair and
/// direction.
public struct GraphEdge: Hashable, Sendable {
    public let source: String
    public let target: String

    public init(source: String, target: String) {
        self.source = source
        self.target = target
    }
}

/// What Obsidian's graph view filters show.
public struct GraphFilterOptions: Equatable, Sendable {
    /// Keeps the files whose path contains every word, ignoring case and accents. As in
    /// Obsidian's search, `tag:#name` keeps the files with that tag or a tag nested under
    /// it, `path:` names a word of the path, and quotes keep spaces in a word.
    public var searchText = ""
    public var showsTags = false
    public var showsAttachments = false
    /// Hides links to files that do not exist.
    public var showsExistingFilesOnly = true
    /// Shows files without any link.
    public var showsOrphans = true

    public init(searchText: String = "", showsTags: Bool = false, showsAttachments: Bool = false,
                showsExistingFilesOnly: Bool = true, showsOrphans: Bool = true) {
        self.searchText = searchText
        self.showsTags = showsTags
        self.showsAttachments = showsAttachments
        self.showsExistingFilesOnly = showsExistingFilesOnly
        self.showsOrphans = showsOrphans
    }
}

/// Which links around a note Obsidian's local graph follows.
public struct LocalGraphOptions: Equatable, Sendable {
    /// How many links away from the note to go.
    public var depth = 1
    public var followsIncomingLinks = true
    public var followsOutgoingLinks = true
    /// Also shows the links between the notes found, not only those on the way out.
    public var showsNeighborLinks = true

    public init(depth: Int = 1, followsIncomingLinks: Bool = true, followsOutgoingLinks: Bool = true, showsNeighborLinks: Bool = true) {
        self.depth = depth
        self.followsIncomingLinks = followsIncomingLinks
        self.followsOutgoingLinks = followsOutgoingLinks
        self.showsNeighborLinks = showsNeighborLinks
    }
}

/// The notes of a vault and the links between them.
public struct LinkGraph: Equatable, Sendable {
    public private(set) var nodes: [GraphNode]
    public private(set) var edges: [GraphEdge]

    public init(nodes: [GraphNode], edges: [GraphEdge]) {
        var seenNodes: Set<String> = []
        self.nodes = nodes.filter { node in seenNodes.insert(node.id).inserted }
        var seenEdges: Set<GraphEdge> = []
        self.edges = edges.filter { edge in edge.source != edge.target && seenNodes.contains(edge.source) && seenNodes.contains(edge.target) && seenEdges.insert(edge).inserted }
    }

    /// The graph with its files, the links between them, links to files that do not
    /// exist, and each file's tags. Link and tag targets need not be among `files`.
    public static func build(files: [VaultPath], links: [(source: VaultPath, target: VaultPath)], unresolvedLinks: [(source: VaultPath, target: String)],
                             tags: [(path: VaultPath, tag: String)]) -> LinkGraph {
        var nodes = files.map(GraphNode.file)
        var edges = links.map { link in GraphEdge(source: link.source.rawValue, target: link.target.rawValue) }
        // Unresolved targets are merged ignoring capitals, as Obsidian merges them.
        var unresolvedNames: [String: String] = [:]
        for link in unresolvedLinks {
            let key = link.target.lowercased()
            let name = unresolvedNames[key] ?? link.target
            if unresolvedNames[key] == nil {
                unresolvedNames[key] = name
                nodes.append(GraphNode(id: name, kind: .unresolved))
            }
            edges.append(GraphEdge(source: link.source.rawValue, target: name))
        }
        var tagNames: [String: String] = [:]
        for assignment in tags {
            let key = assignment.tag.lowercased()
            let name = tagNames[key] ?? "#" + assignment.tag
            if tagNames[key] == nil {
                tagNames[key] = name
                nodes.append(GraphNode(id: name, kind: .tag))
            }
            edges.append(GraphEdge(source: assignment.path.rawValue, target: name))
        }
        return LinkGraph(nodes: nodes, edges: edges)
    }

    /// What a graph shows, as the corner of the graph view names it.
    public struct Counts: Equatable, Sendable {
        public var notes = 0
        public var attachments = 0
        public var tags = 0
        /// Link targets without a file.
        public var unresolved = 0
        /// The lines between files and link targets, a pair linked both ways counted once.
        /// A tag's lines say which notes carry it and are not counted.
        public var links = 0

        public init(notes: Int = 0, attachments: Int = 0, tags: Int = 0, unresolved: Int = 0, links: Int = 0) {
            self.notes = notes
            self.attachments = attachments
            self.tags = tags
            self.unresolved = unresolved
            self.links = links
        }
    }

    public var counts: Counts {
        var counts = Counts()
        var tagIdentifiers: Set<String> = []
        for node in nodes {
            switch node.kind {
            case .note: counts.notes += 1
            case .attachment: counts.attachments += 1
            case .tag: counts.tags += 1; tagIdentifiers.insert(node.id)
            case .unresolved: counts.unresolved += 1
            }
        }
        var linkedPairs: Set<GraphEdge> = []
        for edge in edges where !tagIdentifiers.contains(edge.source) && !tagIdentifiers.contains(edge.target) {
            linkedPairs.insert(edge.source < edge.target ? edge : GraphEdge(source: edge.target, target: edge.source))
        }
        counts.links = linkedPairs.count
        return counts
    }

    /// How many links each node has, in either direction.
    public var linkCounts: [String: Int] {
        var counts: [String: Int] = [:]
        for edge in edges {
            counts[edge.source, default: 0] += 1
            counts[edge.target, default: 0] += 1
        }
        return counts
    }

    /// The graph with what the filters hide left out. Files matched by the search keep
    /// their tags and unresolved links; a node the filters leave without links is an orphan.
    public func filtered(by options: GraphFilterOptions) -> LinkGraph {
        let search = GraphSearch(options.searchText)
        let tagsByFile = search.tags.isEmpty ? [:] : foldedTagsByFile
        let kept = nodes.filter { node in
            switch node.kind {
            case .note: break
            case .attachment: if !options.showsAttachments { return false }
            case .tag: return options.showsTags
            case .unresolved: return !options.showsExistingFilesOnly
            }
            return search.matches(path: node.id, tags: tagsByFile[node.id] ?? [])
        }
        var graph = LinkGraph(nodes: kept, edges: edges)
        // Tags and unresolved links belong to files: without a linking file, they go.
        let linked = Set(graph.edges.flatMap { edge in [edge.source, edge.target] })
        graph.nodes = graph.nodes.filter { node in
            if node.kind == .tag || node.kind == .unresolved { return linked.contains(node.id) }
            return options.showsOrphans || linked.contains(node.id)
        }
        return LinkGraph(nodes: graph.nodes, edges: graph.edges)
    }

    /// Each file's tags, folded as the search folds its words (`#course/vlsi`).
    private var foldedTagsByFile: [String: [String]] {
        let tagIdentifiers = Set(nodes.filter { node in node.kind == .tag }.map(\.id))
        var tagsByFile: [String: [String]] = [:]
        for edge in edges where tagIdentifiers.contains(edge.target) {
            tagsByFile[edge.source, default: []].append(GraphSearch.fold(edge.target))
        }
        return tagsByFile
    }

    /// The nodes within `options.depth` links of `center`, as Obsidian's local graph shows
    /// them. Empty when the center is not in the graph.
    public func neighborhood(of center: String, options: LocalGraphOptions) -> LinkGraph {
        guard nodes.contains(where: { node in node.id == center }) else { return LinkGraph(nodes: [], edges: []) }
        var outgoing: [String: [String]] = [:]
        var incoming: [String: [String]] = [:]
        for edge in edges {
            outgoing[edge.source, default: []].append(edge.target)
            incoming[edge.target, default: []].append(edge.source)
        }
        var reached: Set<String> = [center]
        var pathEdges: Set<GraphEdge> = []
        var frontier: [String] = [center]
        for _ in 0..<max(options.depth, 0) {
            var next: [String] = []
            for node in frontier {
                if options.followsOutgoingLinks {
                    for target in outgoing[node] ?? [] {
                        pathEdges.insert(GraphEdge(source: node, target: target))
                        if reached.insert(target).inserted { next.append(target) }
                    }
                }
                if options.followsIncomingLinks {
                    for source in incoming[node] ?? [] {
                        pathEdges.insert(GraphEdge(source: source, target: node))
                        if reached.insert(source).inserted { next.append(source) }
                    }
                }
            }
            frontier = next
        }
        let keptEdges = options.showsNeighborLinks
            ? edges.filter { edge in reached.contains(edge.source) && reached.contains(edge.target) }
            : edges.filter(pathEdges.contains)
        return LinkGraph(nodes: nodes.filter { node in reached.contains(node.id) }, edges: keptEdges)
    }
}

/// The graph's filter read as Obsidian's search reads it: words of the path, `path:` words,
/// and `tag:` tags, all of which a file must match, ignoring case and accents.
struct GraphSearch {
    private(set) var pathWords: [String] = []
    /// Tags with their `#`, folded.
    private(set) var tags: [String] = []

    init(_ text: String) {
        for word in Self.words(text).map(Self.fold) {
            if word.hasPrefix("tag:") {
                let tag = word.dropFirst("tag:".count)
                guard !tag.isEmpty, tag != "#" else { continue }
                tags.append(tag.hasPrefix("#") ? String(tag) : "#" + tag)
            } else if word.hasPrefix("path:") {
                if word.count > "path:".count { pathWords.append(String(word.dropFirst("path:".count))) }
            } else {
                pathWords.append(word)
            }
        }
    }

    /// The words of the filter, a quoted part one word with its spaces (`path:"Mes Cours/"`).
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var word = ""
        var isQuoted = false
        for character in text {
            if character == "\"" {
                isQuoted.toggle()
            } else if character.isWhitespace && !isQuoted {
                if !word.isEmpty { words.append(word) }
                word = ""
            } else {
                word.append(character)
            }
        }
        if !word.isEmpty { words.append(word) }
        return words
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Whether a file with this path and these folded tags is kept; a tag also matches the
    /// tags nested under it, as `tag:#course` matches `#course/vlsi`.
    func matches(path: String, tags fileTags: [String]) -> Bool {
        let foldedPath = Self.fold(path)
        guard pathWords.allSatisfy({ word in foldedPath.contains(word) }) else { return false }
        return tags.allSatisfy { tag in fileTags.contains { fileTag in fileTag == tag || fileTag.hasPrefix(tag + "/") } }
    }
}
