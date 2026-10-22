import Foundation
import GraphiteCore

/// Where the graph view was left: its zoom and position, what it kept in sight, and the
/// center request it already followed. The whole graph's tab keeps it while other tabs are
/// in front, so the graph comes back as the person left it rather than fitted again.
struct GraphCanvasPlace: Equatable {
    /// What the view keeps in sight while the layout moves.
    enum Framing: Equatable {
        /// Every node, fitted again as the layout moves.
        case allNodes
        /// One node in the middle, as a note's local graph asks.
        case node(String)
        /// Where the person moved or zoomed to.
        case free
    }

    var viewport: GraphViewport
    var framing: Framing
    /// The last center request the view followed, so that coming back to the graph does not
    /// center on it again.
    var servedCenterRequest: GraphCenterRequest?

    /// The whole graph, fitted as it settles.
    static let wholeGraph = GraphCanvasPlace(viewport: GraphViewport(), framing: .allNodes, servedCenterRequest: nil)

    /// Where the view starts: on the node of a center request it has not followed yet, else
    /// where it was kept, else the whole graph.
    static func starting(from kept: GraphCanvasPlace?, centerRequest: GraphCenterRequest?) -> GraphCanvasPlace {
        let place = kept ?? wholeGraph
        guard let centerRequest, centerRequest != place.servedCenterRequest else { return place }
        return GraphCanvasPlace(viewport: place.viewport, framing: .node(centerRequest.identifier), servedCenterRequest: centerRequest)
    }
}
