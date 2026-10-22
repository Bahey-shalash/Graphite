import CoreGraphics

/// Puts a placed class diagram on the page: nodes at their centers, relations from one box's side to the other's
/// through their passing points with their marks and cardinalities, loops beside their classes, then everything
/// moved inside the padding below the title.
struct ClassDiagramPageAssembly {
    /// A cardinality sits 5 points beside a left or right side's end and 7 points above or below its line, or
    /// 9 points beside a top or bottom side's line and 3 points above or below the side: Pele's.
    static let besideVerticalSide = CGVector(dx: 5, dy: 7)
    static let besideHorizontalSide = CGVector(dx: 9, dy: 3)
    /// An end with a cardinality runs straight for its text's room (its width and 10 points on a left or right side,
    /// its row and 6 points on a top or bottom side), at most this share of the way to the next point.
    static let straightEndExtra = CGSize(width: 10, height: 6)
    static let straightEndShare: CGFloat = 0.35
    /// A straight end shorter than this is not worth drawing.
    static let shortestStraightEnd: CGFloat = 4

    let measured: ClassDiagramMeasurement
    let markRowHeight: CGFloat
    let axes: FlowchartFlowAxes
    private(set) var nodeCenters: [CGPoint] = []
    /// By the index of the measurement's edge; nil until the edge is placed.
    private var edges: [ClassDiagramLayoutEdge?]

    init(measured: ClassDiagramMeasurement, markRowHeight: CGFloat, axes: FlowchartFlowAxes) {
        self.measured = measured
        self.markRowHeight = markRowHeight
        self.axes = axes
        edges = Array(repeating: nil, count: measured.edges.count)
    }

    mutating func placeNodes(flowCenters: [CGPoint]) {
        nodeCenters = flowCenters.map(axes.pagePoint)
    }

    /// The edges between two different nodes, along their routes. `layeredEdgeIndices[i]` is the edge of the
    /// placement's `i`-th route.
    mutating func placeEdges(layeredEdgeIndices: [Int], placement: LayeredPlacement) {
        let ends = layeredEdgeIndices.enumerated().flatMap { layeredIndex, edgeIndex in
            routeEnds(of: edgeIndex, route: placement.edgeRoutes[layeredIndex])
        }
        let ports = ClassDiagramEdgePorts(ends: ends, edgeCount: measured.edges.count, nodeCenters: nodeCenters, sizes: measured.sizes,
                                          markRowHeight: markRowHeight)
        var endsByEdge = [(source: ClassDiagramEdgePorts.End?, target: ClassDiagramEdgePorts.End?)](repeating: (nil, nil), count: measured.edges.count)
        for end in ends {
            if end.isSourceEnd { endsByEdge[end.edgeIndex].source = end } else { endsByEdge[end.edgeIndex].target = end }
        }
        for (layeredIndex, edgeIndex) in layeredEdgeIndices.enumerated() {
            guard let sourcePort = ports.sourcePoints[edgeIndex], let targetPort = ports.targetPoints[edgeIndex],
                  let sourceEnd = endsByEdge[edgeIndex].source, let targetEnd = endsByEdge[edgeIndex].target else { continue }
            let route = placement.edgeRoutes[layeredIndex]
            let textCenter = placement.edgeLabelCenters[layeredIndex].map(axes.pagePoint)
                ?? CGPoint(x: (sourcePort.x + targetPort.x) / 2, y: (sourcePort.y + targetPort.y) / 2)
            edges[edgeIndex] = edgeAlong([sourcePort] + route.dropFirst().dropLast().map(axes.pagePoint) + [targetPort], edgeIndex: edgeIndex,
                                         ends: (sourceEnd, targetEnd), textCenter: textCenter)
        }
    }

    /// The two ends of a route on the sides of their nodes facing it, with what orders and spaces them.
    private func routeEnds(of edgeIndex: Int, route: [CGPoint]) -> [ClassDiagramEdgePorts.End] {
        let edge = measured.edges[edgeIndex]
        let last = route.count - 1
        // In a flow that runs down, an end's text goes right of its line when the line bends right or runs straight.
        func isTextAfter(bend: CGFloat) -> Bool { axes.flowIsVertical ? bend >= 0 : bend > 0 }
        return [
            ClassDiagramEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: true, node: edge.source,
                                      side: route[1].y > route[0].y ? axes.downstreamSide : axes.upstreamSide, neighborAlongSide: route[1].x,
                                      cardinalityWidth: edge.sourceCardinality?.size.width ?? 0, isTextAfter: isTextAfter(bend: route[1].x - route[0].x)),
            ClassDiagramEdgePorts.End(edgeIndex: edgeIndex, isSourceEnd: false, node: edge.target,
                                      side: route[last - 1].y < route[last].y ? axes.upstreamSide : axes.downstreamSide,
                                      neighborAlongSide: route[last - 1].x, cardinalityWidth: edge.targetCardinality?.size.width ?? 0,
                                      isTextAfter: isTextAfter(bend: route[last - 1].x - route[last].x)),
        ]
    }

    private func edgeAlong(_ ports: [CGPoint], edgeIndex: Int, ends: (source: ClassDiagramEdgePorts.End, target: ClassDiagramEdgePorts.End),
                           textCenter: CGPoint) -> ClassDiagramLayoutEdge {
        let edge = measured.edges[edgeIndex]
        var points = ports
        if let straight = straightEnd(from: points[0], toward: points[1], end: ends.source) { points.insert(straight, at: 1) }
        if let straight = straightEnd(from: points[points.count - 1], toward: points[points.count - 2], end: ends.target) {
            points.insert(straight, at: points.count - 1)
        }
        let drawn = DiagramRouteDrawing.path(through: points, flowIsVertical: axes.flowIsVertical,
                                             startTrim: ClassDiagramMarkGeometry.lineTrim(for: edge.sourceEnd),
                                             endTrim: ClassDiagramMarkGeometry.lineTrim(for: edge.targetEnd))
        let leaving = CGVector(dx: -drawn.startDirection.dx, dy: -drawn.startDirection.dy)
        return ClassDiagramLayoutEdge(line: edge.line, path: drawn.path,
                                      sourceMark: mark(edge.sourceEnd, tip: points[0], direction: leaving),
                                      targetMark: mark(edge.targetEnd, tip: points[points.count - 1], direction: drawn.endDirection),
                                      text: centeredIfPresent(edge.text, at: textCenter),
                                      sourceCardinality: cardinality(edge.sourceCardinality, at: points[0], side: ends.source.side,
                                                                     isTextAfter: ends.source.isTextAfter),
                                      targetCardinality: cardinality(edge.targetCardinality, at: points[points.count - 1], side: ends.target.side,
                                                                     isTextAfter: ends.target.isTextAfter))
    }

    /// The point an end with a cardinality runs straight out to from its side before it bends, or nil.
    private func straightEnd(from port: CGPoint, toward neighbor: CGPoint, end: ClassDiagramEdgePorts.End) -> CGPoint? {
        guard end.cardinalityWidth > 0 else { return nil }
        let reach = end.side.isHorizontal ? abs(neighbor.y - port.y) : abs(neighbor.x - port.x)
        let room = end.side.isHorizontal ? markRowHeight + Self.straightEndExtra.height : end.cardinalityWidth + Self.straightEndExtra.width
        let length = min(room, reach * Self.straightEndShare)
        guard length >= Self.shortestStraightEnd else { return nil }
        switch end.side {
        case .top: return CGPoint(x: port.x, y: port.y - length)
        case .bottom: return CGPoint(x: port.x, y: port.y + length)
        case .left: return CGPoint(x: port.x - length, y: port.y)
        case .right: return CGPoint(x: port.x + length, y: port.y)
        }
    }

    /// The loops of every class that has relations to itself.
    mutating func placeSelfLoops(_ selfLoops: [[Int]]) {
        for (node, loopEdgeIndices) in selfLoops.enumerated() {
            for (loopIndex, edgeIndex) in loopEdgeIndices.enumerated() {
                let edge = measured.edges[edgeIndex]
                let loop = ClassDiagramSelfLoops.loop(center: nodeCenters[node], boxSize: measured.sizes[node], loopIndex: loopIndex,
                                                      startTrim: ClassDiagramMarkGeometry.lineTrim(for: edge.sourceEnd),
                                                      endTrim: ClassDiagramMarkGeometry.lineTrim(for: edge.targetEnd),
                                                      textWidth: edge.text?.size.width ?? 0)
                let intoBox = CGVector(dx: -1, dy: 0)
                edges[edgeIndex] = ClassDiagramLayoutEdge(
                    line: edge.line, path: loop.path, sourceMark: mark(edge.sourceEnd, tip: loop.leave, direction: intoBox),
                    targetMark: mark(edge.targetEnd, tip: loop.back, direction: intoBox), text: centeredIfPresent(edge.text, at: loop.textCenter),
                    sourceCardinality: cardinality(edge.sourceCardinality, at: loop.leave, side: .right, isTextAfter: false),
                    targetCardinality: cardinality(edge.targetCardinality, at: loop.back, side: .right, isTextAfter: true))
            }
        }
    }

    private func mark(_ end: ClassDiagramRelationEnd, tip: CGPoint, direction: CGVector) -> ClassDiagramRelationMark? {
        end == .none ? nil : ClassDiagramRelationMark(end: end, tip: tip, direction: direction)
    }

    /// A cardinality beside the end at `point`, on the side of its line `isTextAfter` names.
    private func cardinality(_ text: DiagramTextBlock?, at point: CGPoint, side: DiagramSide, isTextAfter: Bool) -> DiagramTextBlock? {
        guard let text else { return nil }
        let width = text.size.width
        let after: CGFloat = isTextAfter ? 1 : -1
        let center: CGPoint
        switch side {
        case .left, .right:
            let outward: CGFloat = side == .left ? -1 : 1
            center = CGPoint(x: point.x + outward * (Self.besideVerticalSide.dx + width / 2),
                             y: point.y + after * (Self.besideVerticalSide.dy + markRowHeight / 2))
        case .top, .bottom:
            let outward: CGFloat = side == .top ? -1 : 1
            center = CGPoint(x: point.x + after * (Self.besideHorizontalSide.dx + width / 2),
                             y: point.y + outward * (Self.besideHorizontalSide.dy + markRowHeight / 2))
        }
        return centered(text, at: center)
    }

    /// `text` centered at `center`, or nil when there is no text.
    private func centeredIfPresent(_ text: DiagramTextBlock?, at center: CGPoint) -> DiagramTextBlock? {
        text.map { text in centered(text, at: center) }
    }

    private func centered(_ text: DiagramTextBlock, at center: CGPoint) -> DiagramTextBlock {
        var placed = text
        placed.center = center
        return placed
    }

    /// The finished layout: everything moved so that the drawing starts `padding` from the top left, below the
    /// title, and centered under the title when the title is wider.
    func finished(font: DiagramFont, title: DiagramTextBlock?, padding: CGFloat, titleGap: CGFloat) -> ClassDiagramLayout {
        let (classes, notes, interfaces) = placedNodes()
        var relations: [ClassDiagramLayoutEdge] = []
        var noteLinks: [ClassDiagramLayoutEdge] = []
        for (edgeIndex, edge) in measured.edges.enumerated() {
            guard let placed = edges[edgeIndex] else { continue }
            if edge.relationIndex == nil { noteLinks.append(placed) } else { relations.append(placed) }
        }
        let bounds = ClassDiagramLayoutBounds.union(frames: classes.map(\.frame) + notes.map(\.frame) + interfaces.map(\.frame), edges: relations + noteLinks)
        let titleSize = title?.size ?? .zero
        let innerWidth = max(bounds.width, titleSize.width)
        let titleHeight = title == nil ? 0 : titleSize.height + titleGap
        let offset = CGVector(dx: padding + (innerWidth - bounds.width) / 2 - bounds.minX, dy: padding + titleHeight - bounds.minY)
        let size = CGSize(width: (innerWidth + 2 * padding).rounded(.up), height: (bounds.height + titleHeight + 2 * padding).rounded(.up))
        var placedTitle = title
        placedTitle?.center = CGPoint(x: size.width / 2, y: padding + titleSize.height / 2)
        return ClassDiagramLayout(size: size, font: font, classes: classes.map { box in box.translated(by: offset) },
                                  notes: notes.map { note in note.translated(by: offset) },
                                  interfaces: interfaces.map { text in text.translated(by: offset) },
                                  relations: relations.map { edge in edge.translated(by: offset) },
                                  noteLinks: noteLinks.map { edge in edge.translated(by: offset) }, title: placedTitle)
    }

    /// The classes' boxes, the notes and the interfaces' names at their nodes' centers.
    private func placedNodes() -> ([ClassDiagramLayoutClass], [ClassDiagramLayoutNote], [DiagramTextBlock]) {
        var classes: [ClassDiagramLayoutClass] = []
        var notes: [ClassDiagramLayoutNote] = []
        var interfaces: [DiagramTextBlock] = []
        for (node, kind) in measured.nodes.enumerated() {
            let center = nodeCenters[node]
            switch kind {
            case .classBox(let boxIndex): classes.append(measured.boxes[boxIndex].placed(at: center))
            case .note(let noteIndex):
                let size = measured.sizes[node]
                notes.append(ClassDiagramLayoutNote(frame: CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width,
                                                                  height: size.height),
                                                    text: centered(measured.noteTexts[noteIndex], at: center)))
            case .interface(let interfaceIndex): interfaces.append(centered(measured.interfaceTexts[interfaceIndex], at: center))
            }
        }
        return (classes, notes, interfaces)
    }
}
