import CoreGraphics

/// The way the ranks of a layout follow each other on a page whose y runs down.
enum LayeredDirection: Equatable, Sendable {
    case topToBottom, bottomToTop, leftToRight, rightToLeft

    /// Whether ranks follow each other down or up the page, rather than across it.
    var runsVertically: Bool { self == .topToBottom || self == .bottomToTop }

    /// The side of a box the flow starts from: the first rank is nearest it.
    var startSide: DiagramSide {
        switch self {
        case .topToBottom: .top
        case .bottomToTop: .bottom
        case .leftToRight: .left
        case .rightToLeft: .right
        }
    }

    /// The side of a box the flow ends at.
    var endSide: DiagramSide {
        switch self {
        case .topToBottom: .bottom
        case .bottomToTop: .top
        case .leftToRight: .right
        case .rightToLeft: .left
        }
    }

    /// An extent on the page as `across` and `along` the ranks.
    func flowSize(of size: CGSize) -> LayeredSize {
        runsVertically ? LayeredSize(across: size.width, along: size.height) : LayeredSize(across: size.height, along: size.width)
    }
}

/// A graph whose nodes may sit in nested boxes, clusters, to lay out in ranks on a page whose y runs down: each box is
/// laid out on its own, in its own direction, then placed in the box around it as one node, as Pele lays out a
/// flowchart's subgraphs (`LayeredClusterLayout`).
struct LayeredClusterGraph {
    /// Each node's size on the page.
    var nodeSizes: [CGSize]
    /// The cluster each node sits directly in, or nil for the top level.
    var nodeClusters: [Int?]
    var clusters: [LayeredCluster]
    /// Edges between two different ends. An edge from a node to itself is drawn beside it and is not laid out here.
    var edges: [LayeredClusterEdge]
    /// The direction of the top level.
    var direction: LayeredDirection
}

/// A box around some nodes and clusters.
struct LayeredCluster: Equatable {
    /// The cluster this one sits directly in, or nil for the top level.
    var parent: Int?
    /// The direction inside the box, or nil for that of the box around it.
    var direction: LayeredDirection?
    var padding: LayeredClusterPadding
    /// The narrowest the box is, so that its title fits.
    var minimumWidth: CGFloat
}

/// The room inside a box around what it holds, on the page.
struct LayeredClusterPadding: Equatable {
    /// On the left and on the right.
    var side: CGFloat
    /// Above, where the title is.
    var top: CGFloat
    var bottom: CGFloat

    static let none = LayeredClusterPadding(side: 0, top: 0, bottom: 0)
}

/// What an edge of a cluster graph starts or ends at: a node, or a box itself.
enum LayeredClusterEnd: Equatable {
    case node(Int)
    case cluster(Int)
}

struct LayeredClusterEdge: Equatable {
    var source: LayeredClusterEnd
    var target: LayeredClusterEnd
    /// The fewest ranks the edge spans, at least 1, in the box where its ends meet.
    var minimumRankSpan: Int
    /// The size of the edge's text on the page, which takes a place of its own between the ranks, or nil.
    var labelSize: CGSize?
}

/// Where a cluster layout put everything on the page, the top left corner at 0.
struct LayeredClusterPlacement: Equatable {
    var nodeCenters: [CGPoint]
    var clusterFrames: [CGRect]
    /// By edge.
    var edgeRoutes: [LayeredClusterRoute]
    /// By edge, the center of its text's place, or nil.
    var edgeLabelCenters: [CGPoint?]
    var size: CGSize
}

/// An edge's way across the page, in the edge's own direction: from its source's center (a node's, or a box's where
/// the edge starts at the box itself) to its target's, through every point it passes, where it crosses a box's border
/// included.
struct LayeredClusterRoute: Equatable {
    var points: [CGPoint]
    /// For each segment between two points, whether the flow it follows runs vertically: the way its S curve leaves
    /// and arrives.
    var segmentsRunVertically: [Bool]

    static let empty = LayeredClusterRoute(points: [], segmentsRunVertically: [])
}

/// Why a cluster graph was not laid out.
enum LayeredClusterLayoutError: Error, Equatable {
    /// The nodes and passing points of the boxes would be more than the limit.
    case tooManyPoints
    /// A cluster sits inside itself through its parents.
    case clusterInsideItself
    /// An edge joins a box and something inside it, or a box and itself.
    case edgeIntoItsOwnCluster
    /// Two edges must leave one rank of a box straight across the flow through the same side, where one would run
    /// through the other's node; or one node must leave through both sides.
    case crossFlowExitsShareARank
}
