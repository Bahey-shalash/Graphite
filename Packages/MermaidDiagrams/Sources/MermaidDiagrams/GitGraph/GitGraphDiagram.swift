/// A Mermaid Git graph (`gitGraph`) as its text describes it, once its statements have been played as Mermaid plays
/// them: the commits in the order they were made, each on its branch with its parents, and the branches in the order
/// their lanes are drawn.
public struct GitGraphDiagram: Equatable, Sendable {
    public internal(set) var direction: GitGraphDirection
    /// `title …` in the diagram, else `title:` in the front matter, else nil.
    public internal(set) var title: String?
    /// The commits in the order the statements make them: commits, merges and cherry-picks.
    public internal(set) var commits: [GitGraphCommit]
    /// The branches in the order their lanes are drawn: by `order:`, a branch without one counting as 0, then in the
    /// order they were created, `main` first.
    public internal(set) var branches: [GitGraphBranch]
    /// `accTitle: …`, the short name a screen reader gives the diagram, or nil.
    public internal(set) var accessibilityTitle: String?
    /// `accDescr: …` or `accDescr { … }`, the longer description a screen reader reads, or nil.
    public internal(set) var accessibilityDescription: String?
    /// Whether the front matter's `config` or a `%%{init: …}%%` directive sets options of Git graphs (`gitGraph:`): the
    /// main branch's name and order, `showBranches`, `showCommitLabel`, `rotateCommitLabel` or `parallelCommits`. They
    /// are not applied, so the layout refuses such a graph rather than draw it otherwise than Mermaid does.
    public internal(set) var setsGitGraphOptions: Bool

    init(direction: GitGraphDirection = .leftToRight, title: String? = nil, commits: [GitGraphCommit] = [], branches: [GitGraphBranch] = [],
         accessibilityTitle: String? = nil, accessibilityDescription: String? = nil, setsGitGraphOptions: Bool = false) {
        self.direction = direction
        self.title = title
        self.commits = commits
        self.branches = branches
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
        self.setsGitGraphOptions = setsGitGraphOptions
    }
}

/// A branch, which the graph draws as a lane.
public struct GitGraphBranch: Equatable, Sendable {
    /// The name statements refer to it by, without quotation marks.
    public let name: String
    /// The name as it is drawn: only `<br>` is markup, other tags stay as written, entity codes are read.
    public let label: DiagramLabel
}

/// One commit of the graph: made by `commit`, `merge` or `cherry-pick`.
public struct GitGraphCommit: Equatable, Sendable {
    /// The id `id:` gives it, or the one made up for it as Pele makes it up (`3-1c6f6a1`: its place in the graph and
    /// seven hexadecimal digits), the same for the same text.
    public let identifier: String
    /// Whether `id:` gave the identifier. A merge shows its identifier only then, as in Mermaid.
    public let hasWrittenIdentifier: Bool
    public let kind: GitGraphCommitKind
    /// `type:` on a commit or a merge, or nil.
    public let type: GitGraphCommitType?
    /// `msg:`, or the text in quotation marks after `commit`; empty when there is none. Pele shows it as a tooltip only,
    /// so it is not drawn.
    public let message: String
    /// The tags drawn beside it, empty ones left out. A cherry-pick without `tag:` has Mermaid's `cherry-pick:<id>`
    /// (`cherry-pick:<id>|parent:<id>` for a merge).
    public let tags: [DiagramLabel]
    /// The branch it was made on, an index into `GitGraphDiagram.branches`.
    public let branchIndex: Int
    /// The commits it follows, as indices into `GitGraphDiagram.commits`, each before it: the branch's previous last
    /// commit (none for the first commit of a branch made from nothing); then, for a merge, the merged branch's last
    /// commit, and for a cherry-pick, the commit it copies.
    public let parentIndices: [Int]
}

/// The statement that made a commit.
public enum GitGraphCommitKind: Equatable, Sendable {
    /// `commit`.
    case commit
    /// `merge`: its second parent is the merged branch's last commit.
    case merge
    /// `cherry-pick`: its second parent is the commit it copies.
    case cherryPick
}

/// `type:` on a commit or a merge, which changes the commit's symbol.
public enum GitGraphCommitType: Equatable, Sendable {
    /// `NORMAL`: a dot (on a merge, a dot instead of the merge's ring).
    case normal
    /// `REVERSE`: a dot with a cross.
    case reverse
    /// `HIGHLIGHT`: a square.
    case highlight
}

/// The way a Git graph's history runs.
public enum GitGraphDirection: Equatable, Sendable, CaseIterable {
    /// `gitGraph`, or `gitGraph LR:`: commits from left to right, one lane per branch from the top down.
    case leftToRight
    /// `gitGraph TB:`: commits from the top down, one lane per branch from left to right.
    case topToBottom
    /// `gitGraph BT:`: commits from the bottom up, one lane per branch from left to right.
    case bottomToTop
}
