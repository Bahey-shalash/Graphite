import CoreGraphics

/// A graph to lay out in ranks, in flow space: `across` is the axis the nodes of one rank are spread along, `along`
/// the axis ranks follow each other on. A top-to-bottom diagram has `across` horizontal; a left-to-right one vertical.
struct LayeredGraph {
    var nodeSizes: [LayeredSize]
    var edges: [LayeredEdge]
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
}

/// The gaps the layout keeps.
struct LayeredSpacing: Equatable {
    /// Between two nodes of one rank.
    var nodeSeparation: CGFloat
    /// Between an edge passing through a rank and its neighbours there.
    var edgeSeparation: CGFloat
    /// Between two ranks of nodes.
    var rankSeparation: CGFloat
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
