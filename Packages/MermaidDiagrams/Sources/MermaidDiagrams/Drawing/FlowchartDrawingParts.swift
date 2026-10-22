import CoreGraphics

/// A laid-out flowchart's geometry grouped by how it is painted, so that drawing it in any colors is a handful of
/// fills and strokes, by Core Graphics (`FlowchartRenderer`) or by a view's own shapes. Back to front, as Pele draws:
/// the edges and their marks, the patches behind edge text and that text, the node shapes and their text, the title.
public struct FlowchartDrawingParts {
    /// Solid edges, stroked one point wide with round caps.
    public let solidEdges: CGPath
    /// Thick edges, stroked 2.5 points wide.
    public let thickEdges: CGPath
    /// Dotted edges, stroked one point wide in dashes of 3 and gaps of 4.
    public let dottedEdges: CGPath
    /// Arrows and circles at the ends of edges, filled in the line color.
    public let filledMarks: CGPath
    /// Crosses at the ends of edges, stroked one point wide in the line color.
    public let strokedMarks: CGPath
    /// The patches behind edge text, filled in the background color.
    public let edgeTextPatches: CGPath
    public let edgeTexts: [DiagramTextBlock]
    /// The node shapes, filled in the surface color.
    public let nodeFills: CGPath
    /// The node shapes' outlines and inner lines, stroked one point wide in the border color.
    public let nodeOutlines: CGPath
    public let nodeTexts: [DiagramTextBlock]
    /// The title, drawn bold, or nil.
    public let title: DiagramTextBlock?

    public static let lineWidth: CGFloat = 1
    public static let thickLineWidth: CGFloat = 2.5
    public static let dottedDashLengths: [CGFloat] = [3, 4]

    /// The corner radius of the patch behind an edge's text.
    static let edgeTextPatchCornerRadius: CGFloat = 3
    /// How much wider than its text the patch behind an edge's text is.
    static let edgeTextPatchExtraWidth: CGFloat = 8

    public init(layout: FlowchartLayout) {
        let edges = EdgePaths(edges: layout.edges)
        let nodes = NodePaths(nodes: layout.nodes)
        solidEdges = edges.solid
        thickEdges = edges.thick
        dottedEdges = edges.dotted
        filledMarks = edges.filledMarks
        strokedMarks = edges.strokedMarks
        edgeTextPatches = edges.textPatches
        edgeTexts = layout.edges.compactMap(\.text)
        nodeFills = nodes.fills
        nodeOutlines = nodes.outlines
        nodeTexts = layout.nodes.map(\.text)
        title = layout.title
    }

    /// The edges' lines by stroke, their marks, and the patches behind their text.
    private struct EdgePaths {
        let solid = CGMutablePath()
        let thick = CGMutablePath()
        let dotted = CGMutablePath()
        let filledMarks = CGMutablePath()
        let strokedMarks = CGMutablePath()
        let textPatches = CGMutablePath()

        init(edges: [FlowchartLayoutEdge]) {
            for edge in edges {
                switch edge.stroke {
                case .solid: solid.addPath(DiagramEdgeDrawing.path(edge.path))
                case .thick: thick.addPath(DiagramEdgeDrawing.path(edge.path))
                case .dotted: dotted.addPath(DiagramEdgeDrawing.path(edge.path))
                case .invisible: break
                }
                if edge.stroke != .invisible {
                    for mark in [edge.sourceMark, edge.targetMark].compactMap({ mark in mark }) {
                        DiagramEdgeDrawing.addMark(mark, filled: filledMarks, stroked: strokedMarks)
                    }
                }
                if let text = edge.text {
                    textPatches.addPath(CGPath(roundedRect: text.frame.insetBy(dx: -FlowchartDrawingParts.edgeTextPatchExtraWidth / 2, dy: 0),
                                               cornerWidth: FlowchartDrawingParts.edgeTextPatchCornerRadius,
                                               cornerHeight: FlowchartDrawingParts.edgeTextPatchCornerRadius, transform: nil))
                }
            }
        }
    }

    /// The node shapes to fill, and their outlines and inner lines to stroke.
    private struct NodePaths {
        let fills = CGMutablePath()
        let outlines = CGMutablePath()

        init(nodes: [FlowchartLayoutNode]) {
            for node in nodes {
                if let outline = FlowchartShapeDrawing.outline(of: node.shape, in: node.frame) {
                    fills.addPath(outline)
                    outlines.addPath(outline)
                }
                if let innerLines = FlowchartShapeDrawing.innerLines(of: node.shape, in: node.frame) { outlines.addPath(innerLines) }
            }
        }
    }
}
