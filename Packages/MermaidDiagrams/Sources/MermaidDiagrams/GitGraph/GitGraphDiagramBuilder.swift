/// Plays a Git graph's statements as Mermaid's Git graph database does (Pele's port of it): a commit goes on the
/// current branch after its last commit, a branch starts from the current branch's last commit and is checked out, a
/// merge and a cherry-pick take a second parent, and a statement the history cannot take is refused with its line,
/// in Mermaid's order of checks. Commits, branches and tags are each a node for `MermaidDiagramLimits.maximumNodeCount`.
struct GitGraphDiagramBuilder {
    /// A branch as it is played: where its lane goes and its last commit, an index into `commits`.
    private struct PlayedBranch {
        let name: String
        let order: Int
        var lastCommitIndex: Int?
    }

    /// The branch every graph starts on, which is first among the branches of order 0.
    static let mainBranchName = "main"

    private let limits: MermaidDiagramLimits
    private var commits: [GitGraphCommit] = []
    private var commitIndexByIdentifier: [String: Int] = [:]
    /// In the order they were created; a commit's `branchIndex` counts in this order until `played()`.
    private var branches: [PlayedBranch] = []
    private var branchIndexByName: [String: Int] = [:]
    private var currentBranchIndex = 0
    private var nodeCount = 0

    init(limits: MermaidDiagramLimits) throws(MermaidDiagramReadError) {
        self.limits = limits
        try addBranch(name: Self.mainBranchName, order: 0, lastCommitIndex: nil)
    }

    mutating func play(_ statement: GitGraphStatement, line: Int) throws(MermaidDiagramReadError) {
        switch statement {
        case .commit(let identifier, let message, let tags, let type):
            try refuseTakenIdentifier(identifier, line: line)
            try addCommit(.commit, identifier: identifier, type: type, message: message, tags: tags, secondParentIndex: nil)
        case .branch(let name, let order):
            guard branchIndexByName[name] == nil else { throw Self.problem(.branchAlreadyExists(name: name), line) }
            try addBranch(name: name, order: order ?? 0, lastCommitIndex: branches[currentBranchIndex].lastCommitIndex)
            currentBranchIndex = branches.count - 1
        case .checkout(let name):
            guard let index = branchIndexByName[name] else { throw Self.problem(.unknownBranch(name: name), line) }
            currentBranchIndex = index
        case .merge(let name, let identifier, let tags, let type):
            try merge(name, identifier: identifier, tags: tags, type: type, line: line)
        case .cherryPick(let identifier, let tags, let parent):
            try cherryPick(identifier: identifier, tags: tags, parent: Self.written(parent), line: line)
        }
    }

    /// The commits, and the branches in the order their lanes are drawn: by order, then in the order they were
    /// created. Each commit's `branchIndex` is its branch's place in that order.
    func played() -> (commits: [GitGraphCommit], branches: [GitGraphBranch]) {
        let laneOrder = branches.indices.sorted { left, right in (branches[left].order, left) < (branches[right].order, right) }
        var laneByCreation = [Int](repeating: 0, count: branches.count)
        for (lane, branchIndex) in laneOrder.enumerated() { laneByCreation[branchIndex] = lane }
        let lanes = laneOrder.map { index in
            GitGraphBranch(name: branches[index].name, label: DiagramLabelDecoder.label(from: branches[index].name, form: .literal))
        }
        return (commits.map { commit in commit.moved(toBranch: laneByCreation[commit.branchIndex]) }, lanes)
    }

    /// `merge`, checked as Mermaid checks it, in its order.
    private mutating func merge(_ name: String, identifier: String?, tags: [String], type: GitGraphCommitType?, line: Int) throws(MermaidDiagramReadError) {
        let currentLast = branches[currentBranchIndex].lastCommitIndex
        let mergedIndex = branchIndexByName[name]
        let mergedLast = mergedIndex.flatMap { index in branches[index].lastCommitIndex }
        if let currentLast, mergedLast != nil, commits[currentLast].branchIndex == mergedIndex { throw Self.problem(.branchMergedIntoItself(name: name), line) }
        if mergedIndex == currentBranchIndex { throw Self.problem(.branchMergedIntoItself(name: name), line) }
        guard let currentLast else { throw Self.problem(.currentBranchWithoutCommits(name: branches[currentBranchIndex].name), line) }
        guard mergedIndex != nil else { throw Self.problem(.unknownBranch(name: name), line) }
        guard let mergedLast else { throw Self.problem(.mergedBranchWithoutCommits(name: name), line) }
        guard mergedLast != currentLast else { throw Self.problem(.branchesShareTheirLastCommit(name: name), line) }
        try refuseTakenIdentifier(identifier, line: line)
        try addCommit(.merge, identifier: identifier, type: type, message: "", tags: tags, secondParentIndex: mergedLast)
    }

    /// `cherry-pick`, checked as Mermaid checks it, in its order. Without `tag:` it is tagged `cherry-pick:<id>`, with
    /// `|parent:<id>` for a merge.
    private mutating func cherryPick(identifier: String?, tags: [String], parent: String?, line: Int) throws(MermaidDiagramReadError) {
        guard let identifier = Self.written(identifier) else { throw Self.problem(.cherryPickWithoutIdentifier, line) }
        guard let sourceIndex = commitIndexByIdentifier[identifier] else { throw Self.problem(.unknownCommit(identifier: identifier), line) }
        let source = commits[sourceIndex]
        if let parent, !source.parentIndices.contains(where: { index in commits[index].identifier == parent }) {
            throw Self.problem(.notAParent(parent: parent, identifier: identifier), line)
        }
        if source.kind == .merge, parent == nil { throw Self.problem(.mergeCherryPickedWithoutParent(identifier: identifier), line) }
        guard source.branchIndex != currentBranchIndex else { throw Self.problem(.cherryPickFromCurrentBranch(identifier: identifier), line) }
        guard branches[currentBranchIndex].lastCommitIndex != nil else {
            throw Self.problem(.currentBranchWithoutCommits(name: branches[currentBranchIndex].name), line)
        }
        let defaultTag = "cherry-pick:" + identifier + (source.kind == .merge ? "|parent:" + (parent ?? "") : "")
        try addCommit(.cherryPick, identifier: nil, type: nil, message: "", tags: tags.isEmpty ? [defaultTag] : tags, secondParentIndex: sourceIndex)
    }

    /// A commit on the current branch, after its last commit and then `secondParentIndex`, with the id written, or one
    /// made up; tags that draw nothing are left out.
    private mutating func addCommit(_ kind: GitGraphCommitKind, identifier: String?, type: GitGraphCommitType?, message: String, tags: [String],
                                    secondParentIndex: Int?) throws(MermaidDiagramReadError) {
        let labels = tags.map { tag in DiagramLabelDecoder.label(from: tag, form: .literal) }.filter { label in !label.isEmpty }
        try count(1 + labels.count)
        let written = Self.written(identifier)
        let index = commits.count
        let commitIdentifier = written ?? GitGraphCommitIdentifier.generated(sequenceNumber: index) { candidate in commitIndexByIdentifier[candidate] != nil }
        commits.append(GitGraphCommit(identifier: commitIdentifier, hasWrittenIdentifier: written != nil, kind: kind, type: type, message: message,
                                      tags: labels, branchIndex: currentBranchIndex,
                                      parentIndices: [branches[currentBranchIndex].lastCommitIndex, secondParentIndex].compactMap { parent in parent }))
        commitIndexByIdentifier[commitIdentifier] = index
        branches[currentBranchIndex].lastCommitIndex = index
    }

    /// Refuses an id `id:` gives that a commit made before has, which Mermaid refuses for a merge. For a commit,
    /// Mermaid warns and keeps the later commit in place of the earlier, so that its graph loses a commit and looks
    /// complete: Graphite refuses it too.
    private func refuseTakenIdentifier(_ identifier: String?, line: Int) throws(MermaidDiagramReadError) {
        guard let identifier = Self.written(identifier), commitIndexByIdentifier[identifier] != nil else { return }
        throw Self.problem(.duplicateCommitIdentifier(identifier), line)
    }

    private mutating func addBranch(name: String, order: Int, lastCommitIndex: Int?) throws(MermaidDiagramReadError) {
        try count(1)
        branchIndexByName[name] = branches.count
        branches.append(PlayedBranch(name: name, order: order, lastCommitIndex: lastCommitIndex))
    }

    private mutating func count(_ nodes: Int) throws(MermaidDiagramReadError) {
        guard nodeCount + nodes <= limits.maximumNodeCount else { throw .tooManyNodes(limit: limits.maximumNodeCount) }
        nodeCount += nodes
    }

    /// A value `id:` or `parent:` wrote, or nil when it wrote none or an empty one, which Mermaid takes as none.
    private static func written(_ value: String?) -> String? {
        value.flatMap { written in written.isEmpty ? nil : written }
    }

    private static func problem(_ problem: GitGraphSyntaxProblem, _ line: Int) -> MermaidDiagramReadError {
        .invalidSyntax(line: line, problem: .gitGraph(problem))
    }
}

extension GitGraphCommit {
    /// The same commit on the branch at `branchIndex`.
    func moved(toBranch branchIndex: Int) -> GitGraphCommit {
        GitGraphCommit(identifier: identifier, hasWrittenIdentifier: hasWrittenIdentifier, kind: kind, type: type, message: message, tags: tags,
                       branchIndex: branchIndex, parentIndices: parentIndices)
    }
}
