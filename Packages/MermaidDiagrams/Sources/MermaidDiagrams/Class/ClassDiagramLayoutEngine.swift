import CoreGraphics

/// Lays a class diagram out in Pele's style: each class a box of compartments sized around its text, notes and
/// lollipop interfaces beside them; the nodes in ranks along the diagram's direction, 40 points apart in a rank and
/// 56 points between ranks (72 when a relation has a cardinality); relations as S curves that spread along the
/// sides they meet, with their marks, text and cardinalities; relations from a class to itself as loops beside it;
/// and the title above.
public enum ClassDiagramLayoutEngine {
    static let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 56)
    /// Between ranks when any relation has a cardinality, which needs room at both ends.
    static let rankSeparationWithCardinalities: CGFloat = 72
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// The room a relation's text takes beyond its lines, for the patch drawn behind it.
    static let edgeTextRoom = CGSize(width: 12, height: 4)
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12

    public static func layout(_ diagram: ClassDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits) throws(ClassDiagramLayoutError) -> ClassDiagramLayout {
        try layout(diagram, measurers: ClassDiagramTextMeasurers(names: typography.boldNodeText, members: typography.edgeText, marks: typography.smallText),
                   font: typography.font, limits: limits)
    }

    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: ClassDiagram, measurers: ClassDiagramTextMeasurers<Measurer>, font: DiagramFont,
                                                       limits: MermaidDiagramLimits) throws(ClassDiagramLayoutError) -> ClassDiagramLayout {
        guard diagram.namespaces.isEmpty else { throw .namespacesNotLaidOut }
        var measured = ClassDiagramMeasurement(diagram: diagram, measurers: measurers)
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        if flowAxes.flowIsVertical { measured.widenCrowdedClasses() }
        let selfLoops = measured.selfLoopEdgeIndices
        let layeredEdgeIndices = measured.edges.indices.filter { edgeIndex in !measured.edges[edgeIndex].isSelfLoop }
        let graph = LayeredGraph(nodeSizes: measured.layoutSizes(selfLoops: selfLoops).map(flowAxes.flowSize(of:)),
                                 edges: layeredEdgeIndices.map { edgeIndex in
                                     let edge = measured.edges[edgeIndex]
                                     let labelSize = edge.text.map { text in
                                         flowAxes.flowSize(of: CGSize(width: text.size.width + edgeTextRoom.width,
                                                                      height: text.size.height + edgeTextRoom.height))
                                     }
                                     return LayeredEdge(source: edge.source, target: edge.target, minimumRankSpan: 1, labelSize: labelSize)
                                 })
        guard let placement = LayeredLayout.place(graph, spacing: spacing(for: measured), maximumPointCount: limits.maximumLayoutPointCount) else {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = ClassDiagramPageAssembly(measured: measured, markRowHeight: measurers.markRowHeight,
                                            axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: placement.extent.height))
        page.placeNodes(flowCenters: placement.nodeCenters)
        page.placeEdges(layeredEdgeIndices: layeredEdgeIndices, placement: placement)
        page.placeSelfLoops(selfLoops)
        let title = diagram.title.map { title in
            DiagramTextBlock(label: DiagramLabel(title), measurer: measurers.names, maximumWidth: .greatestFiniteMagnitude)
        }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }

    /// Pele's gaps, with ranks farther apart when any relation has a cardinality.
    private static func spacing(for measured: ClassDiagramMeasurement) -> LayeredSpacing {
        var spacing = Self.spacing
        if measured.edges.contains(where: { edge in edge.sourceCardinality != nil || edge.targetCardinality != nil }) {
            spacing.rankSeparation = rankSeparationWithCardinalities
        }
        return spacing
    }
}
