import CoreGraphics

/// A flowchart with subgraphs as a graph of nested boxes to lay out (`LayeredClusterLayout`), as Pele lays it out:
/// each group a box with 20 points of room on its sides and below, its title in a band along its top, at least as
/// wide as its title, running in its own direction or in that of the box around it; each node in the box of the group
/// that holds it; and each edge between two different nodes or boxes, a node that stands for a group (`A --> group`)
/// being the group's box.
struct FlowchartClusterGraph {
    /// Pele's room inside a box, on its sides and below it, and above it when the group has no title.
    static let clusterPadding: CGFloat = 20
    /// Between the box's top and its title, and between the title and the box's content.
    static let titleMargin: CGFloat = 8
    /// How much narrower than its title and two paddings a box may be: Pele's.
    static let titleWidthAllowance: CGFloat = 12

    let graph: LayeredClusterGraph
    /// For each node of the diagram, its node in `graph`, or nil for a node that stands for a group.
    let layoutNodeIndices: [Int?]
    /// For each node of the diagram, the group it stands for, or nil.
    let representedSubgraphs: [Int?]
    /// The diagram's edges laid out, in the order of `graph.edges`; an edge from a node to itself loops beside it.
    let layoutEdgeIndices: [Int]
    /// Each group's title, measured, or nil for a group without one.
    let titles: [DiagramTextBlock?]
    /// How many boxes each group's box is inside.
    let depths: [Int]
    /// The side each node's loops go out of, by the direction of the box it is in.
    let loopSides: [DiagramSide]

    /// Fails with `FlowchartLayoutError.subgraphsNotLaidOut` for what is not laid out: a collapsed group, or an edge
    /// from a group to itself.
    init<Measurer: DiagramTextMeasuring>(diagram: FlowchartDiagram, measured: FlowchartMeasurement, titleText: Measurer,
                                         edgeTextRoom: CGSize) throws(FlowchartLayoutError) {
        guard !diagram.subgraphs.contains(where: \.isCollapsed) else { throw .subgraphsNotLaidOut }
        let nesting = FlowchartClusterNesting(diagram: diagram)
        let measuredTitles = diagram.subgraphs.map { subgraph in
            let title = DiagramTextBlock(label: subgraph.title, measurer: titleText, maximumWidth: .greatestFiniteMagnitude)
            return title.lines.isEmpty ? nil : title
        }
        titles = measuredTitles
        depths = nesting.subgraphDepths
        representedSubgraphs = nesting.representedSubgraphs
        let nodeLoopSides: [DiagramSide] = nesting.nodeDirections.map { direction in direction.runsAcross ? .bottom : .right }
        loopSides = nodeLoopSides
        var layoutNodeIndices: [Int?] = []
        var nodeSizes: [CGSize] = []
        var nodeClusters: [Int?] = []
        for node in diagram.nodes.indices {
            guard nesting.representedSubgraphs[node] == nil else {
                layoutNodeIndices.append(nil)
                continue
            }
            layoutNodeIndices.append(nodeSizes.count)
            nodeSizes.append(measured.layoutSize(of: node, loopSide: nodeLoopSides[node]))
            nodeClusters.append(nesting.nodeSubgraphs[node])
        }
        self.layoutNodeIndices = layoutNodeIndices
        let clusters = diagram.subgraphs.indices.map { subgraph in
            Self.cluster(parent: nesting.subgraphParents[subgraph], direction: diagram.subgraphs[subgraph].direction, title: measuredTitles[subgraph])
        }
        let edges = try Self.edges(of: diagram, measured: measured, edgeTextRoom: edgeTextRoom, layoutNodeIndices: layoutNodeIndices,
                                   representedSubgraphs: nesting.representedSubgraphs)
        layoutEdgeIndices = edges.diagramIndices
        graph = LayeredClusterGraph(nodeSizes: nodeSizes, nodeClusters: nodeClusters, clusters: clusters, edges: edges.layout,
                                    direction: diagram.direction.layeredDirection)
    }

    /// A group's box: Pele's padding, the title's band along the top, at least as wide as the title.
    private static func cluster(parent: Int?, direction: FlowchartDirection?, title: DiagramTextBlock?) -> LayeredCluster {
        let titleSize = title?.size ?? .zero
        let top = title == nil ? clusterPadding : titleSize.height + 2 * titleMargin
        return LayeredCluster(parent: parent, direction: direction?.layeredDirection,
                              padding: LayeredClusterPadding(side: clusterPadding, top: top, bottom: clusterPadding),
                              minimumWidth: titleSize.width + 2 * clusterPadding - titleWidthAllowance)
    }

    /// The edges between two different ends, with their texts' room; an edge from a group to itself fails.
    private static func edges(of diagram: FlowchartDiagram, measured: FlowchartMeasurement, edgeTextRoom: CGSize, layoutNodeIndices: [Int?],
                              representedSubgraphs: [Int?]) throws(FlowchartLayoutError) -> (layout: [LayeredClusterEdge], diagramIndices: [Int]) {
        func end(of node: Int) -> LayeredClusterEnd {
            if let subgraph = representedSubgraphs[node] { return .cluster(subgraph) }
            return .node(layoutNodeIndices[node] ?? 0)
        }
        var layout: [LayeredClusterEdge] = []
        var diagramIndices: [Int] = []
        for (edgeIndex, edge) in diagram.edges.enumerated() {
            let source = end(of: edge.sourceIndex)
            let target = end(of: edge.targetIndex)
            if source == target {
                if case .cluster = source { throw .subgraphsNotLaidOut }
                continue
            }
            let labelSize = measured.edgeTexts[edgeIndex].map { text in
                CGSize(width: text.size.width + edgeTextRoom.width, height: text.size.height + edgeTextRoom.height)
            }
            layout.append(LayeredClusterEdge(source: source, target: target, minimumRankSpan: edge.minimumRankSpan, labelSize: labelSize))
            diagramIndices.append(edgeIndex)
        }
        return (layout, diagramIndices)
    }
}
