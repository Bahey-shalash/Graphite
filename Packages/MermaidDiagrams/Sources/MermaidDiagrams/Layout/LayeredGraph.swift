import CoreGraphics

/// A graph to lay out in ranks, in flow space: `across` is the axis the nodes of one rank are spread along, `along`
/// the axis ranks follow each other on. A top-to-bottom diagram has `across` horizontal; a left-to-right one vertical.
struct LayeredGraph {
    var nodeSizes: [LayeredSize]
    var edges: [LayeredEdge]
    /// Where each node must go beyond what its edges ask, by node; empty when every node is free, as in a graph that is
    /// not a box of a cluster layout (`LayeredClusterLayout`).
    var nodePlacements: [LayeredNodePlacement] = []
}

/// Where a node must go beyond what its edges ask: what a box laid out as its own graph needs, where an edge that
/// crosses the box's border passes through a point of it.
enum LayeredNodePlacement: Equatable {
    case free
    /// A point of the border the flow starts from: ranked before every other node, the border separation before the
    /// first rank. Its edges run from it, whichever way they are written, and close no cycle.
    case startBorder
    /// A point of the border the flow ends at: ranked after every other node; its edges run to it.
    case endBorder
    /// First across its rank, so that an edge can leave it straight across the flow to the border on that side.
    case firstInRank
    /// Last across its rank.
    case lastInRank

    var isBorder: Bool { self == .startBorder || self == .endBorder }
}

/// An extent in flow space.
struct LayeredSize: Equatable {
    var across: CGFloat
    var along: CGFloat
}

/// An edge between two different nodes. Edges from a node to itself are laid out beside the node, not in ranks.
struct LayeredEdge: Equatable {
    var source: Int
    var target: Int
    /// The fewest ranks the edge spans, at least 1.
    var minimumRankSpan: Int
    /// The extent of the edge's text, which takes a place of its own between the ranks, or nil.
    var labelSize: LayeredSize?
    /// How far across from its source's center the edge leaves, where it is held at a point of a box's side: the
    /// layout places the source so that this point, not its center, lines up with the edge. 0 for the center.
    var sourceOffset: CGFloat = 0
    /// How far across from its target's center the edge arrives.
    var targetOffset: CGFloat = 0
}

/// The gaps the layout keeps.
struct LayeredSpacing: Equatable {
    /// Between two nodes of one rank.
    var nodeSeparation: CGFloat
    /// Between an edge passing through a rank and its neighbours there.
    var edgeSeparation: CGFloat
    /// Between two ranks of nodes.
    var rankSeparation: CGFloat
    /// Between a rank of border points and the rank next to it, or nil for the rank separation.
    var borderSeparation: CGFloat?
}

/// Where the layout put everything, in flow space, with the smallest `across` and `along` at 0.
struct LayeredPlacement: Equatable {
    var nodeCenters: [CGPoint]
    /// For each edge, the points it passes through from its source's center to its target's center, both included,
    /// in the edge's own direction even where the layout turned it around to break a cycle.
    var edgeRoutes: [[CGPoint]]
    /// For each edge, the center of its text's place, or nil.
    var edgeLabelCenters: [CGPoint?]
    /// `x` is the extent across, `y` along.
    var extent: CGSize
}
