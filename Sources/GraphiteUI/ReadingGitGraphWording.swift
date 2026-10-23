import MermaidDiagrams

extension GitGraphSyntaxProblem {
    /// What is wrong on the line, as the end of the sentence `ReadingDiagramFailure.explanation` starts.
    var explanation: String {
        switch self {
        case .expectedBranchName: "a branch’s name is missing"
        case .expectedCommitType: "“type:” is not followed by NORMAL, REVERSE or HIGHLIGHT"
        case .expectedOrder: "“order:” is not followed by a whole number"
        case .branchAlreadyExists(let name): "the branch “\(name)” exists already"
        case .unknownBranch(let name): "the branch “\(name)” does not exist yet"
        case .branchMergedIntoItself(let name): "the branch “\(name)” would be merged into itself"
        case .currentBranchWithoutCommits(let name): "the branch “\(name)” has no commit yet"
        case .mergedBranchWithoutCommits(let name): "the merged branch “\(name)” has no commit yet"
        case .branchesShareTheirLastCommit(let name): "the branch “\(name)” has nothing to merge: both branches end on the same commit"
        case .duplicateCommitIdentifier(let identifier): "the commit id “\(identifier)” is used twice"
        case .cherryPickWithoutIdentifier: "“cherry-pick” does not name a commit with “id:”"
        case .unknownCommit(let identifier): "the commit “\(identifier)” does not exist"
        case .cherryPickFromCurrentBranch(let identifier): "the commit “\(identifier)” is already on the current branch"
        case .mergeCherryPickedWithoutParent(let identifier): "the merge “\(identifier)” is cherry-picked without “parent:”"
        case .notAParent(let parent, let identifier): "“\(parent)” is not a parent of the commit “\(identifier)”"
        }
    }
}
