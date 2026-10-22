import CoreGraphics

/// Lays a flowchart out in Pele's style: each node's shape sized around its text, wrapped at 200 points; the nodes in
/// ranks along the diagram's direction, 40 points apart in a rank and 48 points between ranks; edges as S curves
/// that spread along the sides they meet; edges to a node itself as loops beside it; and the title above.
public enum FlowchartLayoutEngine {
    static let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 48)
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// The widest a line of text is before it wraps.
    static let wrappingWidth: CGFloat = 200
    /// The room an edge's text takes beyond its lines, for the patch drawn behind it.
    static let edgeTextRoom = CGSize(width: 12, height: 4)
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12

    public static func layout(_ diagram: FlowchartDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits) throws(FlowchartLayoutError) -> FlowchartLayout {
        try layout(diagram, nodeText: typography.nodeText, edgeText: typography.edgeText, font: typography.font, limits: limits)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: FlowchartDiagram, nodeText: Measurer, edgeText: Measurer, font: DiagramFont,
                                                       limits: MermaidDiagramLimits) throws(FlowchartLayoutError) -> FlowchartLayout {
        guard diagram.subgraphs.isEmpty else { throw .subgraphsNotLaidOut }
        let measured = FlowchartMeasurement(diagram: diagram, nodeText: nodeText, edgeText: edgeText, wrappingWidth: wrappingWidth)
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let layeredEdgeIndices = diagram.edges.indices.filter { edgeIndex in diagram.edges[edgeIndex].sourceIndex != diagram.edges[edgeIndex].targetIndex }
        let graph = LayeredGraph(nodeSizes: measured.layoutSizes(loopSide: flowAxes.loopSide).map(flowAxes.flowSize(of:)),
                                 edges: layeredEdgeIndices.map { edgeIndex in
                                     let edge = diagram.edges[edgeIndex]
                                     let labelSize = measured.edgeTexts[edgeIndex].map { text in
                                         flowAxes.flowSize(of: CGSize(width: text.size.width + edgeTextRoom.width,
                                                                      height: text.size.height + edgeTextRoom.height))
                                     }
                                     return LayeredEdge(source: edge.sourceIndex, target: edge.targetIndex, minimumRankSpan: edge.minimumRankSpan,
                                                        labelSize: labelSize)
                                 })
        guard let placement = LayeredLayout.place(graph, spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount) else {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = FlowchartPageAssembly(diagram: diagram, measured: measured,
                                         axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: placement.extent.height))
        page.placeNodes(flowCenters: placement.nodeCenters)
        page.placeEdges(layeredEdgeIndices: layeredEdgeIndices, placement: placement)
        page.placeSelfLoops()
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: nodeText, maximumWidth: .greatestFiniteMagnitude) }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }
}
