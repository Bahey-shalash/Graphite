import CoreGraphics

/// A mindmap's text measured and its nodes sized: what the layout needs before it places anything.
struct MindmapMeasurement {
    let texts: [DiagramTextBlock]
    let outlines: [MindmapNodeOutline]
    let sizes: [CGSize]

    /// Measures each node's text, wrapped at `wrappingWidth`, and sizes its outline around it. A text is at least
    /// one line high, so that an empty one keeps its node's height.
    init(diagram: MindmapDiagram, measurer: some DiagramTextMeasuring, wrappingWidth: CGFloat) {
        var texts: [DiagramTextBlock] = []
        var outlines: [MindmapNodeOutline] = []
        var sizes: [CGSize] = []
        texts.reserveCapacity(diagram.nodes.count)
        outlines.reserveCapacity(diagram.nodes.count)
        sizes.reserveCapacity(diagram.nodes.count)
        for (index, node) in diagram.nodes.enumerated() {
            let text = DiagramTextBlock(label: node.label, measurer: measurer, maximumWidth: wrappingWidth)
            let outline = MindmapNodeOutline(shape: node.shape, isRoot: index == 0, hasChildren: !node.childIndices.isEmpty)
            texts.append(text)
            outlines.append(outline)
            sizes.append(outline.size(around: CGSize(width: text.size.width, height: max(text.size.height, measurer.lineHeight))))
        }
        self.texts = texts
        self.outlines = outlines
        self.sizes = sizes
    }
}
