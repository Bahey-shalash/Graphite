/// Why a Git graph was not laid out.
public enum GitGraphLayoutError: Error, Equatable, Sendable {
    /// The front matter or a directive sets options of Git graphs (`GitGraphDiagram.setsGitGraphOptions`), which the
    /// layout does not apply: drawn without them, the graph would differ from Mermaid's and look complete.
    case optionsNotApplied
}
