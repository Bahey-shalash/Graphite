import CoreGraphics

/// An entity relationship diagram's text measured and its boxes sized: what the layout needs before it places
/// anything.
struct EntityRelationshipMeasurement {
    let boxes: [EntityRelationshipMeasuredBox]
    /// Each relationship's label, or nil when it has none.
    let labels: [DiagramTextBlock?]
    /// For each entity, the indexes of its relationships with itself, in their written order.
    let selfRelationshipIndices: [[Int]]
    /// For each entity, the band of its loops' side each of its relationships with itself takes.
    let loopBands: [[CGFloat]]
    /// Whether loops leave their boxes' bottom (ranks run across) rather than their right (ranks run down).
    let loopsLeaveBelow: Bool

    /// The widest a relationship's label is before it wraps.
    static let labelWrappingWidth: CGFloat = 200

    init<Measurer>(diagram: EntityRelationshipDiagram, measurers: EntityRelationshipTextMeasurers<Measurer>, loopsLeaveBelow: Bool) {
        self.loopsLeaveBelow = loopsLeaveBelow
        labels = diagram.relationships.map { relationship in
            let label = DiagramTextBlock(label: relationship.label, measurer: measurers.row, maximumWidth: Self.labelWrappingWidth)
            return label.lines.isEmpty ? nil : label
        }
        var selfRelationshipIndices = [[Int]](repeating: [], count: diagram.entities.count)
        for (index, relationship) in diagram.relationships.enumerated() where relationship.firstEntityIndex == relationship.secondEntityIndex {
            selfRelationshipIndices[relationship.firstEntityIndex].append(index)
        }
        self.selfRelationshipIndices = selfRelationshipIndices
        let labels = labels
        loopBands = selfRelationshipIndices.map { indices in
            indices.map { index in EntityRelationshipSelfLoops.band(labelSize: labels[index]?.size, leavesBelow: loopsLeaveBelow) }
        }
        boxes = zip(diagram.entities, loopBands).map { entity, bands in
            let bandsLength = bands.isEmpty ? 0 : bands.reduce(0, +) + EntityRelationshipSelfLoops.sideMargin
            let minimumSize = loopsLeaveBelow ? CGSize(width: bandsLength, height: 0) : CGSize(width: 0, height: bandsLength)
            return EntityRelationshipBoxMeasurement.box(for: entity, measurers: measurers, minimumSize: minimumSize)
        }
    }

    /// Each entity's size in its rank: its box, widened on both sides across the flow by the room its loops take.
    func layoutSizes() -> [CGSize] {
        boxes.enumerated().map { entity, box in
            let indices = selfRelationshipIndices[entity]
            guard !indices.isEmpty else { return box.size }
            let room = 2 * EntityRelationshipSelfLoops.room(labelSizes: indices.map { index in labels[index]?.size }, leavesBelow: loopsLeaveBelow)
            return loopsLeaveBelow ? CGSize(width: box.size.width, height: box.size.height + room)
                                   : CGSize(width: box.size.width + room, height: box.size.height)
        }
    }
}
