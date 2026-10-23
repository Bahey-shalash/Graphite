import CoreGraphics

/// Lays out a graph whose nodes sit in nested boxes, as Pele's compound layout does: each box is laid out on its own,
/// in ranks, in its own direction, from the deepest boxes up, and then placed in the box around it as one node of its
/// size, so that what a box holds stays together inside it and no two boxes overlap. An edge that crosses a box's
/// border passes through a point of it on the side facing where the edge goes: on the side the box's flow starts from
/// or ends at, a border point ranked before or after everything in the box; on another side, straight across the flow
/// from its node, which is first or last in its rank. Outside, the box's edge is held at that point.
struct LayeredClusterLayout {
    private let graph: LayeredClusterGraph
    private let hierarchy: LayeredClusterHierarchy
    private let spacing: LayeredSpacing
    private let maximumPointCount: Int
    private var pointCount = 0
    /// By level, the size of its box.
    private var boxSizes: [CGSize]
    /// By item, its center in the box of its level, from the box's top left corner.
    private var itemCenters: [CGPoint]
    /// By edge, its route in the box of its level edge, and the center of its text there.
    private var levelRoutes: [LayeredClusterRoute?]
    private var labelCenters: [CGPoint?]
    /// By level and crossing, the route from the inner item to the border (or back) and the point on the border.
    private var crossingRoutes: [[LayeredClusterRoute]]
    private var crossingPoints: [[CGPoint]]

    /// Lays `graph` out, its boxes padded as each cluster asks, within `maximumPointCount` nodes and passing points in
    /// all its boxes together.
    static func place(_ graph: LayeredClusterGraph, spacing: LayeredSpacing,
                      maximumPointCount: Int) throws(LayeredClusterLayoutError) -> LayeredClusterPlacement {
        var hierarchy = try LayeredClusterHierarchy(graph)
        LayeredClusterCrossingSides.settle(&hierarchy, graph: graph)
        var layout = LayeredClusterLayout(graph: graph, hierarchy: hierarchy, spacing: spacing, maximumPointCount: maximumPointCount)
        for level in hierarchy.topDownLevels.reversed() { try layout.layOut(level: level) }
        return layout.placement()
    }

    private init(graph: LayeredClusterGraph, hierarchy: LayeredClusterHierarchy, spacing: LayeredSpacing, maximumPointCount: Int) {
        self.graph = graph
        self.hierarchy = hierarchy
        self.spacing = spacing
        self.maximumPointCount = maximumPointCount
        boxSizes = Array(repeating: .zero, count: graph.clusters.count + 1)
        itemCenters = Array(repeating: .zero, count: graph.nodeSizes.count + graph.clusters.count)
        levelRoutes = Array(repeating: nil, count: graph.edges.count)
        labelCenters = Array(repeating: nil, count: graph.edges.count)
        crossingRoutes = hierarchy.crossings.map { crossings in Array(repeating: .empty, count: crossings.count) }
        crossingPoints = hierarchy.crossings.map { crossings in Array(repeating: .zero, count: crossings.count) }
    }

    /// Lays one level out, its nested boxes laid out already.
    private mutating func layOut(level: Int) throws(LayeredClusterLayoutError) {
        let items = hierarchy.levelItems[level]
        let padding = level == 0 ? LayeredClusterPadding.none : graph.clusters[level - 1].padding
        let minimumWidth = level == 0 ? 0 : graph.clusters[level - 1].minimumWidth
        guard !items.isEmpty else {
            boxSizes[level] = CGSize(width: max(2 * padding.side, minimumWidth), height: padding.top + padding.bottom)
            return
        }
        let levelGraph = try LayeredClusterLevelGraph(level: level, hierarchy: hierarchy, graph: graph, itemSize: itemSize(of:),
                                                      heldOffset: heldOffset(of:edgeIndex:isLeaving:direction:))
        guard let placement = LayeredLayout.place(levelGraph.graph, spacing: spacing, maximumPointCount: maximumPointCount - pointCount) else {
            throw .tooManyPoints
        }
        pointCount += placement.nodeCenters.count + placement.edgeRoutes.reduce(0) { count, route in count + route.count - 2 }
        try levelGraph.checkCrossFlowExits(in: placement)
        let box = LayeredClusterBox(direction: hierarchy.levelDirections[level], content: placement.extent, padding: padding, minimumWidth: minimumWidth)
        boxSizes[level] = box.size
        for (local, item) in items.enumerated() { itemCenters[item] = box.pagePoint(placement.nodeCenters[local]) }
        placeLevelEdges(of: level, levelGraph: levelGraph, placement: placement, box: box)
        placeCrossings(of: level, levelGraph: levelGraph, placement: placement, box: box)
    }

    private func itemSize(of item: Int) -> CGSize {
        hierarchy.isCluster(item) ? boxSizes[hierarchy.boxLevel(ofClusterItem: item)] : graph.nodeSizes[item]
    }

    /// How far across from `item`'s center the edge is held, in a level running in `direction`: where it crosses the
    /// border of `item`'s box when the edge's end is inside it; 0 otherwise.
    private func heldOffset(of item: Int, edgeIndex: Int, isLeaving: Bool, direction: LayeredDirection) -> CGFloat {
        guard let point = heldPoint(of: item, edgeIndex: edgeIndex, isLeaving: isLeaving) else { return 0 }
        let size = itemSize(of: item)
        return direction.runsVertically ? point.x - size.width / 2 : point.y - size.height / 2
    }

    /// Where an edge crosses the border of `item`'s box, from the box's top left corner, when its end is inside it.
    private func heldPoint(of item: Int, edgeIndex: Int, isLeaving: Bool) -> CGPoint? {
        guard let index = LayeredClusterCrossingSides.heldCrossingIndex(of: item, edgeIndex: edgeIndex, isLeaving: isLeaving,
                                                                        hierarchy: hierarchy, graph: graph) else { return nil }
        return crossingPoints[hierarchy.boxLevel(ofClusterItem: item)][index]
    }

    /// `heldPoint` in the box of `item`'s level, or `item`'s center when the edge ends at it.
    private func endPoint(of item: Int, edgeIndex: Int, isLeaving: Bool) -> CGPoint {
        guard let point = heldPoint(of: item, edgeIndex: edgeIndex, isLeaving: isLeaving) else { return itemCenters[item] }
        let size = itemSize(of: item)
        return CGPoint(x: itemCenters[item].x - size.width / 2 + point.x, y: itemCenters[item].y - size.height / 2 + point.y)
    }

    private mutating func placeLevelEdges(of level: Int, levelGraph: LayeredClusterLevelGraph, placement: LayeredPlacement, box: LayeredClusterBox) {
        for (position, levelEdge) in hierarchy.levelEdges[level].enumerated() {
            var points = placement.edgeRoutes[position].map(box.pagePoint)
            points[0] = endPoint(of: levelEdge.sourceItem, edgeIndex: levelEdge.edgeIndex, isLeaving: true)
            points[points.count - 1] = endPoint(of: levelEdge.targetItem, edgeIndex: levelEdge.edgeIndex, isLeaving: false)
            levelRoutes[levelEdge.edgeIndex] = LayeredClusterRoute(points: points, segmentsRunVertically: Array(repeating: box.direction.runsVertically,
                                                                                                                 count: points.count - 1))
            labelCenters[levelEdge.edgeIndex] = placement.edgeLabelCenters[position].map(box.pagePoint)
        }
    }

    /// Each crossing's route inside the box: through its border point and on to the border, or straight across the
    /// flow from its pinned item.
    private mutating func placeCrossings(of level: Int, levelGraph: LayeredClusterLevelGraph, placement: LayeredPlacement, box: LayeredClusterBox) {
        for (index, crossing) in hierarchy.crossings[level].enumerated() {
            let inner = endPoint(of: crossing.innerItem, edgeIndex: crossing.edgeIndex, isLeaving: crossing.isLeaving)
            var points: [CGPoint]
            var runsVertically: [Bool]
            if let layeredEdge = levelGraph.borderEdgeIndices[index] {
                points = placement.edgeRoutes[layeredEdge].map(box.pagePoint)
                if crossing.isLeaving { points[0] = inner } else { points[points.count - 1] = inner }
                let borderPoint = box.borderPoint(on: crossing.side, from: crossing.isLeaving ? points[points.count - 1] : points[0])
                if crossing.isLeaving { points.append(borderPoint) } else { points.insert(borderPoint, at: 0) }
                runsVertically = Array(repeating: box.direction.runsVertically, count: points.count - 1)
            } else {
                let borderPoint = box.borderPoint(on: crossing.side, from: inner)
                points = crossing.isLeaving ? [inner, borderPoint] : [borderPoint, inner]
                runsVertically = [crossing.side.isHorizontal]
            }
            crossingPoints[level][index] = crossing.isLeaving ? points[points.count - 1] : points[0]
            crossingRoutes[level][index] = LayeredClusterRoute(points: points, segmentsRunVertically: runsVertically)
        }
    }

    /// Everything on the page: each box placed from the top level down, and each edge's route joined from its parts.
    private func placement() -> LayeredClusterPlacement {
        var levelOrigins = [CGPoint](repeating: .zero, count: boxSizes.count)
        var pageCenters = itemCenters
        for level in hierarchy.topDownLevels {
            for item in hierarchy.levelItems[level] {
                pageCenters[item] = moved(itemCenters[item], by: levelOrigins[level])
                guard hierarchy.isCluster(item) else { continue }
                let boxLevel = hierarchy.boxLevel(ofClusterItem: item)
                levelOrigins[boxLevel] = CGPoint(x: pageCenters[item].x - boxSizes[boxLevel].width / 2, y: pageCenters[item].y - boxSizes[boxLevel].height / 2)
            }
        }
        let frames = graph.clusters.indices.map { cluster in CGRect(origin: levelOrigins[cluster + 1], size: boxSizes[cluster + 1]) }
        let labels = graph.edges.indices.map { edgeIndex in
            labelCenters[edgeIndex].map { center in moved(center, by: levelOrigins[hierarchy.edgeLevels[edgeIndex]]) }
        }
        return LayeredClusterPlacement(nodeCenters: Array(pageCenters.prefix(graph.nodeSizes.count)), clusterFrames: frames,
                                       edgeRoutes: graph.edges.indices.map { edgeIndex in joinedRoute(of: edgeIndex, levelOrigins: levelOrigins) },
                                       edgeLabelCenters: labels, size: boxSizes[0])
    }

    private func moved(_ point: CGPoint, by origin: CGPoint) -> CGPoint {
        CGPoint(x: point.x + origin.x, y: point.y + origin.y)
    }

    /// An edge's route: out of each box its source is inside, across the level where its ends meet, into each box its
    /// target is inside.
    private func joinedRoute(of edgeIndex: Int, levelOrigins: [CGPoint]) -> LayeredClusterRoute {
        let level = hierarchy.edgeLevels[edgeIndex]
        var route = LayeredClusterRouteJoining()
        var item = hierarchy.item(of: graph.edges[edgeIndex].source)
        while hierarchy.itemLevels[item] != level {
            let boxLevel = hierarchy.itemLevels[item]
            if let index = hierarchy.crossingIndex(level: boxLevel, edgeIndex: edgeIndex, isLeaving: true) {
                route.append(crossingRoutes[boxLevel][index], offset: levelOrigins[boxLevel])
            }
            item = hierarchy.clusterItem(ofBoxLevel: boxLevel)
        }
        if let levelRoute = levelRoutes[edgeIndex] { route.append(levelRoute, offset: levelOrigins[level]) }
        var inward: [Int] = []
        item = hierarchy.item(of: graph.edges[edgeIndex].target)
        while hierarchy.itemLevels[item] != level {
            inward.append(hierarchy.itemLevels[item])
            item = hierarchy.clusterItem(ofBoxLevel: hierarchy.itemLevels[item])
        }
        for boxLevel in inward.reversed() {
            if let index = hierarchy.crossingIndex(level: boxLevel, edgeIndex: edgeIndex, isLeaving: false) {
                route.append(crossingRoutes[boxLevel][index], offset: levelOrigins[boxLevel])
            }
        }
        return route.route
    }
}

/// Joins the parts of an edge's route, each moved by its box's origin; a point that repeats the last is dropped.
private struct LayeredClusterRouteJoining {
    /// Two points closer than this, in points, are one.
    static let samePointDistance: CGFloat = 0.01

    private(set) var route = LayeredClusterRoute(points: [], segmentsRunVertically: [])

    mutating func append(_ part: LayeredClusterRoute, offset: CGPoint) {
        for (index, point) in part.points.enumerated() {
            let moved = CGPoint(x: point.x + offset.x, y: point.y + offset.y)
            if let last = route.points.last {
                guard abs(last.x - moved.x) >= Self.samePointDistance || abs(last.y - moved.y) >= Self.samePointDistance else { continue }
                let segment = index == 0 ? 0 : index - 1
                route.segmentsRunVertically.append(part.segmentsRunVertically.isEmpty ? true : part.segmentsRunVertically[segment])
            }
            route.points.append(moved)
        }
    }
}
