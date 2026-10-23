import CoreGraphics

/// Lays an entity relationship diagram out in Pele's style: each entity a box sized around its name and attribute
/// table; the boxes in ranks along the diagram's direction, from the entity written first in a relationship to the
/// one written second, 48 points apart in a rank and 64 points between ranks; relationships as lines that leave
/// and meet the boxes straight and curve between, spread along the sides they meet, with a label wrapped at 200
/// points on its own rank; relationships of an entity with itself as loops beside it; and the title above.
public enum EntityRelationshipLayoutEngine {
    static let spacing = LayeredSpacing(nodeSeparation: 48, edgeSeparation: 20, rankSeparation: 64)
    /// Around the whole diagram.
    static let padding: CGFloat = 8
    /// The room a label takes beyond its lines, for the patch drawn behind it.
    static let labelRoom = CGSize(width: 12, height: 4)
    /// Between the title and the diagram.
    static let titleGap: CGFloat = 12

    public static func layout(_ diagram: EntityRelationshipDiagram, typography: DiagramTypography,
                              limits: MermaidDiagramLimits) throws(EntityRelationshipLayoutError) -> EntityRelationshipLayout {
        try layout(diagram, nameText: typography.nodeText, rowText: typography.edgeText, font: typography.font, limits: limits)
    }

    /// - Parameters:
    ///   - nameText: Measures the entities' names and the title.
    ///   - rowText: Measures the attribute rows and the labels; keys are measured from it at their own size.
    static func layout<Measurer: DiagramTextMeasuring>(_ diagram: EntityRelationshipDiagram, nameText: Measurer, rowText: Measurer, font: DiagramFont,
                                                       limits: MermaidDiagramLimits) throws(EntityRelationshipLayoutError) -> EntityRelationshipLayout {
        guard diagram.subgraphCount == 0 else { throw .subgraphsNotLaidOut }
        let flowAxes = FlowchartFlowAxes(direction: diagram.direction, alongExtent: 0)
        let measured = EntityRelationshipMeasurement(diagram: diagram, measurers: EntityRelationshipTextMeasurers(name: nameText, row: rowText),
                                                     loopsLeaveBelow: !flowAxes.flowIsVertical)
        let layeredIndices = diagram.relationships.indices.filter { index in
            diagram.relationships[index].firstEntityIndex != diagram.relationships[index].secondEntityIndex
        }
        let graph = LayeredGraph(nodeSizes: measured.layoutSizes().map(flowAxes.flowSize(of:)), edges: layeredIndices.map { index in
            let relationship = diagram.relationships[index]
            let labelSize = measured.labels[index].map { label in
                flowAxes.flowSize(of: CGSize(width: label.size.width + labelRoom.width, height: label.size.height + labelRoom.height))
            }
            return LayeredEdge(source: relationship.firstEntityIndex, target: relationship.secondEntityIndex, minimumRankSpan: 1, labelSize: labelSize)
        })
        guard let placement = LayeredLayout.place(graph, spacing: spacing, maximumPointCount: limits.maximumLayoutPointCount) else {
            throw .tooManyLayoutPoints(limit: limits.maximumLayoutPointCount)
        }
        var page = EntityRelationshipPageAssembly(diagram: diagram, measured: measured,
                                                  axes: FlowchartFlowAxes(direction: diagram.direction, alongExtent: placement.extent.height))
        page.placeBoxes(flowCenters: placement.nodeCenters)
        page.placeRelationships(layeredIndices: layeredIndices, placement: placement)
        page.placeSelfRelationships()
        let title = diagram.title.map { title in DiagramTextBlock(label: DiagramLabel(title), measurer: nameText, maximumWidth: .greatestFiniteMagnitude) }
        return page.finished(font: font, title: title, padding: padding, titleGap: titleGap)
    }
}
