/// What the Git graph reader found wrong on a line, beyond the problems every type shares: a statement its grammar
/// does not take, or one the history played so far cannot take, which Mermaid refuses too.
public enum GitGraphSyntaxProblem: Equatable, Sendable {
    /// A branch's name was expected after `branch`, `checkout`, `switch` or `merge`: a name or text in quotation marks.
    case expectedBranchName
    /// `type:` is not followed by `NORMAL`, `REVERSE` or `HIGHLIGHT`.
    case expectedCommitType
    /// `order:` is not followed by a whole number.
    case expectedOrder
    /// `branch` names a branch that exists already.
    case branchAlreadyExists(name: String)
    /// `checkout`, `switch` or `merge` names a branch not created yet.
    case unknownBranch(name: String)
    /// `merge` names the current branch, or the branch whose last commit the current branch still starts from.
    case branchMergedIntoItself(name: String)
    /// `merge` or `cherry-pick` on a branch that has no commit yet, by the current branch's name.
    case currentBranchWithoutCommits(name: String)
    /// `merge` names a branch that has no commit yet.
    case mergedBranchWithoutCommits(name: String)
    /// `merge` names a branch whose last commit is the current branch's: there is nothing to merge.
    case branchesShareTheirLastCommit(name: String)
    /// `id:` gives a commit or a merge the id of a commit made before it.
    case duplicateCommitIdentifier(String)
    /// `cherry-pick` has no `id:` naming the commit it copies.
    case cherryPickWithoutIdentifier
    /// `cherry-pick` names a commit that does not exist.
    case unknownCommit(identifier: String)
    /// `cherry-pick` names a commit of the current branch.
    case cherryPickFromCurrentBranch(identifier: String)
    /// `cherry-pick` copies a merge without `parent:` naming which of its parents it follows.
    case mergeCherryPickedWithoutParent(identifier: String)
    /// `parent:` names a commit that is none of the cherry-picked commit's parents.
    case notAParent(parent: String, identifier: String)
}
