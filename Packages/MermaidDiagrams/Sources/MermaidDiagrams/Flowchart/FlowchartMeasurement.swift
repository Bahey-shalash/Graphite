import CoreGraphics

/// A flowchart's text measured and its shapes sized: what the layout needs before it places anything.
struct FlowchartMeasurement {
    let nodeTexts: [DiagramTextBlock]
    let shapeSizes: [CGSize]
    /// How far below each shape's center its text's center is.
    let textOffsets: [CGFloat]
    /// Each edge's text, or nil.
    let edgeTexts: [DiagramTextBlock?]
    /// For each node, the indexes of its edges to itself, in their written order.
    let selfLoopEdgeIndices: [[Int]]

    init<Measurer: DiagramTextMeasuring>(diagram: FlowchartDiagram, nodeText: Measurer, edgeText: Measurer, wrappingWidth: CGFloat) {
        var nodeTexts: [DiagramTextBlock] = []
        var shapeSizes: [CGSize] = []
        var textOffsets: [CGFloat] = []
        nodeTexts.reserveCapacity(diagram.nodes.count)
        for node in diagram.nodes {
            let text = DiagramTextBlock(label: node.label, measurer: nodeText, maximumWidth: wrappingWidth)
            let (size, textOffset) = FlowchartShapeGeometry.size(of: node.shape, textSize: text.size)
            nodeTexts.append(text)
            shapeSizes.append(size)
            textOffsets.append(textOffset)
        }
        self.nodeTexts = nodeTexts
        self.shapeSizes = shapeSizes
        self.textOffsets = textOffsets
        edgeTexts = diagram.edges.map { edge in
            edge.label.map { label in DiagramTextBlock(label: label, measurer: edgeText, maximumWidth: wrappingWidth) }
                .flatMap { text in text.lines.isEmpty ? nil : text }
        }
        var selfLoopEdgeIndices = [[Int]](repeating: [], count: diagram.nodes.count)
        for (edgeIndex, edge) in diagram.edges.enumerated() where edge.sourceIndex == edge.targetIndex {
            selfLoopEdgeIndices[edge.sourceIndex].append(edgeIndex)
        }
        self.selfLoopEdgeIndices = selfLoopEdgeIndices
    }

    /// Each node's size in its rank: its shape, widened on both sides across the flow by the room its loops take.
    func layoutSizes(loopSide: DiagramSide) -> [CGSize] {
        shapeSizes.indices.map { node in layoutSize(of: node, loopSide: loopSide) }
    }

    /// One node's size in its rank, its loops going out of `loopSide`.
    func layoutSize(of node: Int, loopSide: DiagramSide) -> CGSize {
        let size = shapeSizes[node]
        let loopEdgeIndices = selfLoopEdgeIndices[node]
        guard !loopEdgeIndices.isEmpty else { return size }
        let room = FlowchartSelfLoops.room(textSizes: loopEdgeIndices.map { edgeIndex in edgeTexts[edgeIndex]?.size }, loopSide: loopSide)
        return loopSide == .right ? CGSize(width: size.width + 2 * room, height: size.height)
                                  : CGSize(width: size.width, height: size.height + 2 * room)
    }
}
