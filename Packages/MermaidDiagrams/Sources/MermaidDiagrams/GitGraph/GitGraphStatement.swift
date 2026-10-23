/// A statement of a Git graph as it is written, before it is played: what Mermaid's grammar reads of it.
enum GitGraphStatement: Equatable {
    /// `commit` with its `id:`, `msg:` (or text in quotation marks), `tag:` and `type:`, in any order; a later value
    /// replaces an earlier one, and tags add up.
    case commit(identifier: String?, message: String, tags: [String], type: GitGraphCommitType?)
    /// `branch` with its name and `order:`.
    case branch(name: String, order: Int?)
    /// `checkout` or `switch` with a branch's name.
    case checkout(name: String)
    /// `merge` with the merged branch's name, then its `id:`, `tag:` and `type:`.
    case merge(name: String, identifier: String?, tags: [String], type: GitGraphCommitType?)
    /// `cherry-pick` with its `id:`, `tag:` and `parent:`.
    case cherryPick(identifier: String?, tags: [String], parent: String?)
}
