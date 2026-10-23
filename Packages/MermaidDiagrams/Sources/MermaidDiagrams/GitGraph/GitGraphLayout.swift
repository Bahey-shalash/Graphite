import CoreGraphics

/// A Git graph laid out on a page whose origin is the top left corner and whose y runs down, in points. Drawing it
/// needs only colors: every position, path and text measurement is here. Lane `k` and what is on it take the series
/// color `k`.
public struct GitGraphLayout: Equatable, Sendable {
    public let size: CGSize
    /// The font the title was measured in; branch names, commit ids and tags are measured in it at their own sizes.
    public let font: DiagramFont
    public let direction: GitGraphDirection
    /// One lane per branch, in the diagram's order of branches.
    public let lanes: [GitGraphLayoutLane]
    /// The lines from each commit's parents to it, commit by commit.
    public let connectors: [GitGraphLayoutConnector]
    /// The commits in the order they were made.
    public let commits: [GitGraphLayoutCommit]
    /// The diagram's title above it, or nil.
    public let title: DiagramTextBlock?
}

/// A branch's lane: a dashed line from before the graph's first commit to past its last, and the branch's name in a
/// box at the line's start.
public struct GitGraphLayoutLane: Equatable, Sendable {
    public let lineStart: CGPoint
    public let lineEnd: CGPoint
    /// The box behind the name, filled in the lane's color; nil for a branch whose name draws nothing.
    public let nameFrame: CGRect?
    /// The branch's name, drawn in the background color; nil for a name that draws nothing.
    public let name: DiagramTextBlock?
}

/// A line from a commit's parent to the commit.
public struct GitGraphLayoutConnector: Equatable, Sendable {
    public let path: DiagramPath
    /// The lane whose color the line takes: the commit's, or the merged branch's for the line a merge takes from it.
    public let laneIndex: Int
    public let style: GitGraphConnectorStyle
}

/// How a line between two commits is drawn.
public enum GitGraphConnectorStyle: Equatable, Sendable {
    /// Straight along a lane, from a commit to the next one on its branch.
    case alongLane
    /// Curved from one lane to another: to a branch's first commit from where the branch started, or to a merge from
    /// the branch it merges.
    case acrossLanes
    /// Dashed and curved: to a cherry-pick from the commit it copies.
    case cherryPick
}

/// A commit: its symbol on its lane, its id and its tags.
public struct GitGraphLayoutCommit: Equatable, Sendable {
    public let center: CGPoint
    public let laneIndex: Int
    public let symbol: GitGraphCommitSymbol
    /// The commit's id beside it; nil for a cherry-pick and a merge without a written id, which Mermaid does not label.
    public let label: GitGraphLayoutCommitLabel?
    public let tags: [GitGraphLayoutTag]
}

/// How a commit is drawn in its lane's color.
public enum GitGraphCommitSymbol: Equatable, Sendable {
    /// A dot.
    case normal
    /// A dot crossed in the background color.
    case reverse
    /// A square.
    case highlight
    /// A ring around a small dot, filled in the background color between them.
    case merge
    /// A dot with a cherry drawn on it in the background color.
    case cherryPick
}

/// A commit's id, turned an eighth of a turn as Pele turns it, on a patch of the background color so that no line runs
/// through it.
public struct GitGraphLayoutCommitLabel: Equatable, Sendable {
    /// The text, centered where it is drawn, before it is turned about its center.
    public let text: DiagramTextBlock
    /// How far the text and its patch turn about the text's center, in radians, clockwise on a page whose y runs down:
    /// negative up to the right, positive down to the right.
    public let angle: CGFloat
    /// The patch's size, centered on the text and turned with it.
    public let patchSize: CGSize
}

/// A tag beside its commit: a box pointed on its left, with a hole near the point, and its text.
public struct GitGraphLayoutTag: Equatable, Sendable {
    /// The box, its point included.
    public let frame: CGRect
    public let text: DiagramTextBlock
}
