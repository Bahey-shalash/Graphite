import CoreGraphics

/// Puts a placed flowchart on the page: nodes at their centers, edges from the outline of one shape to the other's
/// through their passing points, loops beside their nodes, then everything moved inside the padding below the title.
struct FlowchartPageAssembly {
    let diagram: FlowchartDiagram
    let measured: FlowchartMeasurement
    let axes: FlowchartFlowAxes
    private(set) var nodeCenters: [CGPoint] = []
    /// By edge index; nil until the edge is placed.
    private var edges: [FlowchartLayoutEdge?]

    init(diagram: FlowchartDiagram, measured: FlowchartMeasurement, axes: FlowchartFlowAxes) {
        self.diagram = diagram
        self.measured = measured
        self.axes = axes
        edges = Array(repeating: nil, count: diagram.edges.count)
    }

    mutating func placeNodes(flowCenters: [CGPoint]) {
        nodeCenters = flowCenters.map(axes.pagePoint)
    }

    /// The edges between two different nodes, along their routes. `layeredEdgeIndices[i]` is the edge of the
    /// placement's `i`-th route.
    mutating func placeEdges(layeredEdgeIndices: [Int], placement: LayeredPlacement) {
        var ends: [FlowchartEdgePorts.End] = []
        for (layeredIndex, edgeIndex) in layeredEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex]
            let edge = diagram.edges[edgeIndex]
            let leavesDownstream = route[1].y > route[0].y
            let arrivesFromUpstream = route[route.count - 2].y < route[route.count - 1].y
            ends.append(FlowchartEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: true, node: edge.sourceIndex,
                                               side: leavesDownstream ? axes.downstreamSide : axes.upstreamSide, neighborAcross: route[1].x))
            ends.append(FlowchartEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: false, node: edge.targetIndex,
                                               side: arrivesFromUpstream ? axes.upstreamSide : axes.downstreamSide,
                                               neighborAcross: route[route.count - 2].x))
        }
        let shapes = diagram.nodes.map(\.shape)
        let ports = FlowchartEdgePorts(ends: ends, nodeCenters: nodeCenters, shapes: shapes, shapeSizes: measured.shapeSizes)
        for (layeredIndex, edgeIndex) in layeredEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex]
            guard let sourcePoint = ports.sourcePoints[edgeIndex], let targetPoint = ports.targetPoints[edgeIndex] else { continue }
            let points = [sourcePoint] + route.dropFirst().dropLast().map(axes.pagePoint) + [targetPoint]
            let textCenter = placement.edgeLabelCenters[layeredIndex].map(axes.pagePoint)
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            edges[edgeIndex] = edgeAlong(points, edgeIndex: edgeIndex, textCenter: textCenter)
        }
    }

    private func edgeAlong(_ points: [CGPoint], edgeIndex: Int, textCenter: CGPoint) -> FlowchartLayoutEdge {
        let edge = diagram.edges[edgeIndex]
        let drawn = DiagramRouteDrawing.path(through: points, flowIsVertical: axes.flowIsVertical,
                                             startTrim: DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead),
                                             endTrim: DiagramEdgeMark.lineTrim(for: edge.targetArrowhead))
        let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
        return FlowchartLayoutEdge(stroke: edge.stroke, path: drawn.path,
                                   sourceMark: mark(edge.sourceArrowhead, tip: points[0], direction: leaving),
                                   targetMark: mark(edge.targetArrowhead, tip: points[points.count - 1], direction: drawn.endDirection),
                                   text: centered(measured.edgeTexts[edgeIndex], at: textCenter))
    }

    /// The loops of every node that has edges to itself.
    mutating func placeSelfLoops() {
        for (node, loopEdgeIndices) in measured.selfLoopEdgeIndices.enumerated() {
            for (loopIndex, edgeIndex) in loopEdgeIndices.enumerated() {
                let edge = diagram.edges[edgeIndex]
                let loop = FlowchartSelfLoops.loop(center: nodeCenters[node], shape: diagram.nodes[node].shape, size: measured.shapeSizes[node],
                                                   loopSide: axes.loopSide, loopIndex: loopIndex, textSize: measured.edgeTexts[edgeIndex]?.size)
                let arriving = unitVector(from: loop.control2, to: loop.back)
                let leaving = unitVector(from: loop.control1, to: loop.leave)
                let endTrim = DiagramEdgeMark.lineTrim(for: edge.targetArrowhead)
                let startTrim = DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead)
                let start = CGPoint(x: loop.leave.x - leaving.dx * startTrim, y: loop.leave.y - leaving.dy * startTrim)
                let end = CGPoint(x: loop.back.x - arriving.dx * endTrim, y: loop.back.y - arriving.dy * endTrim)
                let path = DiagramPath(start: start, segments: [.curve(to: end, control1: loop.control1, control2: loop.control2)])
                edges[edgeIndex] = FlowchartLayoutEdge(stroke: edge.stroke, path: path,
                                                       sourceMark: mark(edge.sourceArrowhead, tip: loop.leave, direction: leaving),
                                                       targetMark: mark(edge.targetArrowhead, tip: loop.back, direction: arriving),
                                                       text: loop.textCenter.flatMap { center in centered(measured.edgeTexts[edgeIndex], at: center) })
            }
        }
    }

    private func mark(_ arrowhead: FlowchartArrowhead, tip: CGPoint, direction: CGVector) -> DiagramEdgeMark? {
        arrowhead == .none ? nil : DiagramEdgeMark(arrowhead: arrowhead, tip: tip, direction: direction)
    }

    private func centered(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        guard var text else { return nil }
        text.center = center
        return text
    }

    private func unitVector(from start: CGPoint, to end: CGPoint) -> CGVector {
        let length = max(((end.x - start.x) * (end.x - start.x) + (end.y - start.y) * (end.y - start.y)).squareRoot(), 0.0001)
        return CGVector(dx: (end.x - start.x) / length, dy: (end.y - start.y) / length)
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat) -> FlowchartLayout {
        let nodes = diagram.nodes.indices.map { node in
            var text = measured.nodeTexts[node]
            text.center = CGPoint(x: nodeCenters[node].x, y: nodeCenters[node].y + measured.textOffsets[node])
            let size = measured.shapeSizes[node]
            return FlowchartLayoutNode(shape: diagram.nodes[node].shape,
                                       frame: CGRect(x: nodeCenters[node].x - size.width / 2, y: nodeCenters[node].y - size.height / 2,
                                                     width: size.width, height: size.height),
                                       text: text)
        }
        let placedEdges = edges.compactMap { edge in edge }
        let bounds = FlowchartLayoutBounds.union(nodes: nodes, edges: placedEdges)
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        return FlowchartLayout(size: size, font: font, nodes: nodes.map { node in node.translated(by: offset) },
                               edges: placedEdges.map { edge in edge.translated(by: offset) }, title: placedTitle)
    }
}
