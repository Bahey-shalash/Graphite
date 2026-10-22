import CoreGraphics

/// Puts a placed flowchart on the page: nodes at their centers, edges from the outline of one shape to the other's
/// through their passing points, loops beside their nodes, the boxes of its groups with their titles, then everything
/// moved inside the padding below the title.
struct FlowchartPageAssembly {
    let diagram: FlowchartDiagram
    let measured: FlowchartMeasurement
    let axes: FlowchartFlowAxes
    private(set) var nodeCenters: [CGPoint] = []
    /// By edge index; nil until the edge is placed.
    private var edges: [FlowchartLayoutEdge?]
    /// A flowchart with groups: its nodes in boxes, which nodes stand for boxes, and each node's loop side.
    private var clustered: FlowchartClusterGraph?
    private var clusters: [FlowchartLayoutCluster] = []
    /// For each edge placed through boxes, the points it passes, its ends on their outlines: where it crosses a box's top.
    private var edgePoints: [[CGPoint]] = []

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
        let ports = FlowchartEdgePorts(ends: ends, edgeCount: diagram.edges.count, nodeCenters: nodeCenters, shapes: shapes,
                                       shapeSizes: measured.shapeSizes)
        for (layeredIndex, edgeIndex) in layeredEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layeredIndex]
            guard let sourcePoint = ports.sourcePoints[edgeIndex], let targetPoint = ports.targetPoints[edgeIndex] else { continue }
            let points = [sourcePoint] + route.dropFirst().dropLast().map(axes.pagePoint) + [targetPoint]
            let textCenter = placement.edgeLabelCenters[layeredIndex].map(axes.pagePoint)
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            edges[edgeIndex] = edgeAlong(points, edgeIndex: edgeIndex, textCenter: textCenter)
        }
    }

    private func edgeAlong(_ points: [CGPoint], edgeIndex: Int, textCenter: CGPoint, segmentsRunVertically: [Bool]? = nil) -> FlowchartLayoutEdge {
        let edge = diagram.edges[edgeIndex]
        let startTrim = DiagramEdgeMark.lineTrim(for: edge.sourceArrowhead)
        let endTrim = DiagramEdgeMark.lineTrim(for: edge.targetArrowhead)
        let drawn = segmentsRunVertically.map { axes in
            DiagramRouteDrawing.path(through: points, segmentsRunVertically: axes, startTrim: startTrim, endTrim: endTrim)
        } ?? DiagramRouteDrawing.path(through: points, flowIsVertical: axes.flowIsVertical, startTrim: startTrim, endTrim: endTrim)
        let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
        return FlowchartLayoutEdge(stroke: edge.stroke, path: drawn.path,
                                   sourceMark: mark(edge.sourceArrowhead, tip: points[0], direction: leaving),
                                   targetMark: mark(edge.targetArrowhead, tip: points[points.count - 1], direction: drawn.endDirection),
                                   text: centered(measured.edgeTexts[edgeIndex], at: textCenter))
    }

    /// The loops of every node that has edges to itself.
    mutating func placeSelfLoops() {
        for (node, loopEdgeIndices) in measured.selfLoopEdgeIndices.enumerated() where clustered?.representedSubgraphs[node] == nil {
            for (loopIndex, edgeIndex) in loopEdgeIndices.enumerated() {
                let edge = diagram.edges[edgeIndex]
                let loop = FlowchartSelfLoops.loop(center: nodeCenters[node], shape: diagram.nodes[node].shape, size: measured.shapeSizes[node],
                                                   loopSide: clustered?.loopSides[node] ?? axes.loopSide, loopIndex: loopIndex,
                                                   textSize: measured.edgeTexts[edgeIndex]?.size)
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

    /// The nodes of a flowchart laid out in boxes, at their centers on the page; a node that stands for a group at the
    /// center of its box, where it is not drawn.
    mutating func placeNodes(clustered: FlowchartClusterGraph, placement: LayeredClusterPlacement) {
        self.clustered = clustered
        nodeCenters = diagram.nodes.indices.map { node in
            if let subgraph = clustered.representedSubgraphs[node] {
                return CGPoint(x: placement.clusterFrames[subgraph].midX, y: placement.clusterFrames[subgraph].midY)
            }
            return placement.nodeCenters[clustered.layoutNodeIndices[node] ?? 0]
        }
    }

    /// The edges of a flowchart laid out in boxes, along their routes: each end on the outline of its node or box, on
    /// the side its route leaves or arrives by, spread along it with the other ends there; each segment an S along its
    /// own flow.
    mutating func placeEdges(clustered: FlowchartClusterGraph, placement: LayeredClusterPlacement) {
        var ends: [FlowchartEdgePorts.End] = []
        func endItem(of node: Int) -> Int { clustered.representedSubgraphs[node].map { subgraph in diagram.nodes.count + subgraph } ?? node }
        for (layoutIndex, edgeIndex) in clustered.layoutEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layoutIndex]
            let edge = diagram.edges[edgeIndex]
            ends.append(Self.routeEnd(of: route, edgeIndex: edgeIndex, isSourceEnd: true, item: endItem(of: edge.sourceIndex)))
            ends.append(Self.routeEnd(of: route, edgeIndex: edgeIndex, isSourceEnd: false, item: endItem(of: edge.targetIndex)))
        }
        let boxCenters = placement.clusterFrames.map { frame in CGPoint(x: frame.midX, y: frame.midY) }
        let ports = FlowchartEdgePorts(ends: ends, edgeCount: diagram.edges.count, nodeCenters: nodeCenters + boxCenters,
                                       shapes: diagram.nodes.map { node in node.shape } + Array(repeating: .rectangle, count: boxCenters.count),
                                       shapeSizes: measured.shapeSizes + placement.clusterFrames.map { frame in frame.size },
                                       keptClear: Self.borderCrossings(of: placement, firstBoxNode: diagram.nodes.count))
        for (layoutIndex, edgeIndex) in clustered.layoutEdgeIndices.enumerated() {
            let route = placement.edgeRoutes[layoutIndex]
            guard let sourcePoint = ports.sourcePoints[edgeIndex], let targetPoint = ports.targetPoints[edgeIndex] else { continue }
            let points = [sourcePoint] + route.points.dropFirst().dropLast() + [targetPoint]
            edgePoints.append(points)
            let textCenter = placement.edgeLabelCenters[layoutIndex]
                ?? CGPoint(x: (sourcePoint.x + targetPoint.x) / 2, y: (sourcePoint.y + targetPoint.y) / 2)
            edges[edgeIndex] = edgeAlong(points, edgeIndex: edgeIndex, textCenter: textCenter, segmentsRunVertically: route.segmentsRunVertically)
        }
    }

    /// Where edges cross the boxes' borders, by `FlowchartEdgePorts.sideKey` of the box (numbered after the nodes, from
    /// `firstBoxNode`) and its side, as offsets from the side's middle: an edge that ends at a box keeps clear of them.
    private static func borderCrossings(of placement: LayeredClusterPlacement, firstBoxNode: Int) -> [Int: [CGFloat]] {
        let tolerance: CGFloat = 0.01
        var crossings: [Int: [CGFloat]] = [:]
        for route in placement.edgeRoutes {
            for point in route.points.dropFirst().dropLast() {
                for (box, frame) in placement.clusterFrames.enumerated() {
                    let alongTop = point.x > frame.minX && point.x < frame.maxX
                    let alongSide = point.y > frame.minY && point.y < frame.maxY
                    let side: DiagramSide? = if alongTop && abs(point.y - frame.minY) < tolerance { .top }
                        else if alongTop && abs(point.y - frame.maxY) < tolerance { .bottom }
                        else if alongSide && abs(point.x - frame.minX) < tolerance { .left }
                        else if alongSide && abs(point.x - frame.maxX) < tolerance { .right }
                        else { nil }
                    guard let side else { continue }
                    let offset = side.isHorizontal ? point.x - frame.midX : point.y - frame.midY
                    crossings[FlowchartEdgePorts.sideKey(node: firstBoxNode + box, side: side), default: []].append(offset)
                }
            }
        }
        return crossings
    }

    /// An end of a route through boxes: the side of its node or box that its first or last segment leaves or arrives
    /// by, along that segment's flow, and where along the side the route goes next.
    private static func routeEnd(of route: LayeredClusterRoute, edgeIndex: Int, isSourceEnd: Bool, item: Int) -> FlowchartEdgePorts.End {
        let points = route.points
        let end = isSourceEnd ? points[0] : points[points.count - 1]
        let next = isSourceEnd ? points[1] : points[points.count - 2]
        let runsVertically = isSourceEnd ? route.segmentsRunVertically[0] : route.segmentsRunVertically[route.segmentsRunVertically.count - 1]
        let side: DiagramSide = runsVertically ? (next.y > end.y ? .bottom : .top) : (next.x > end.x ? .right : .left)
        return FlowchartEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: isSourceEnd, node: item, side: side,
                                      neighborAcross: side.isHorizontal ? next.x : next.y)
    }

    /// The groups' boxes, each title along its box's top, clear of the edges where it can be.
    mutating func placeClusters(clustered: FlowchartClusterGraph, placement: LayeredClusterPlacement) {
        clusters = placement.clusterFrames.enumerated().map { subgraph, frame in
            let title = clustered.titles[subgraph].map { title in FlowchartClusterTitles.placed(title, in: frame, edgePoints: edgePoints) }
            return FlowchartLayoutCluster(frame: frame, title: title?.title, depth: clustered.depths[subgraph], isTitleCrossed: title?.isCrossed ?? false)
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
        let drawnNodeIndices = diagram.nodes.indices.filter { node in clustered?.representedSubgraphs[node] == nil }
        let nodes = drawnNodeIndices.map { node in
            var text = measured.nodeTexts[node]
            text.center = CGPoint(x: nodeCenters[node].x, y: nodeCenters[node].y + measured.textOffsets[node])
            let size = measured.shapeSizes[node]
            return FlowchartLayoutNode(shape: diagram.nodes[node].shape,
                                       frame: CGRect(x: nodeCenters[node].x - size.width / 2, y: nodeCenters[node].y - size.height / 2,
                                                     width: size.width, height: size.height),
                                       text: text)
        }
        let placedEdges = edges.compactMap { edge in edge }
        let bounds = clusters.reduce(FlowchartLayoutBounds.union(nodes: nodes, edges: placedEdges)) { bounds, cluster in bounds.union(cluster.frame) }
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        return FlowchartLayout(size: size, font: font, nodes: nodes.map { node in node.translated(by: offset) },
                               edges: placedEdges.map { edge in edge.translated(by: offset) }, title: placedTitle,
                               clusters: clusters.map { cluster in cluster.translated(by: offset) })
    }
}
