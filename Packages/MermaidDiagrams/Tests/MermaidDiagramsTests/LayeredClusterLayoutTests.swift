import XCTest
@testable import MermaidDiagrams

final class LayeredClusterLayoutTests: XCTestCase {
    private let spacing = LayeredSpacing(nodeSeparation: 40, edgeSeparation: 16, rankSeparation: 48, borderSeparation: 20)
    private let padding = LayeredClusterPadding(side: 20, top: 36, bottom: 20)
    private let nodeSize = CGSize(width: 60, height: 40)
    private let accuracy: CGFloat = 0.01

    private func cluster(in parent: Int? = nil, direction: LayeredDirection? = nil, minimumWidth: CGFloat = 0) -> LayeredCluster {
        LayeredCluster(parent: parent, direction: direction, padding: padding, minimumWidth: minimumWidth)
    }

    private func edge(_ source: LayeredClusterEnd, _ target: LayeredClusterEnd) -> LayeredClusterEdge {
        LayeredClusterEdge(source: source, target: target, minimumRankSpan: 1, labelSize: nil)
    }

    private func place(nodeClusters: [Int?], clusters: [LayeredCluster], edges: [LayeredClusterEdge],
                       direction: LayeredDirection = .topToBottom) throws -> LayeredClusterPlacement {
        try LayeredClusterLayout.place(LayeredClusterGraph(nodeSizes: Array(repeating: nodeSize, count: nodeClusters.count), nodeClusters: nodeClusters,
                                                           clusters: clusters, edges: edges, direction: direction),
                                       spacing: spacing, maximumPointCount: 1_000)
    }

    private func frame(of node: Int, in placement: LayeredClusterPlacement) -> CGRect {
        let center = placement.nodeCenters[node]
        return CGRect(x: center.x - nodeSize.width / 2, y: center.y - nodeSize.height / 2, width: nodeSize.width, height: nodeSize.height)
    }

    private func inner(_ frame: CGRect) -> CGRect {
        CGRect(x: frame.minX + padding.side, y: frame.minY + padding.top, width: frame.width - 2 * padding.side,
               height: frame.height - padding.top - padding.bottom).insetBy(dx: -accuracy, dy: -accuracy)
    }

    func testABoxHoldsItsNodesInsideItsPaddingAndKeepsTheOthersOut() throws {
        let placement = try place(nodeClusters: [nil, 0, 0, nil], clusters: [cluster()],
                                  edges: [edge(.node(0), .node(1)), edge(.node(1), .node(2)), edge(.node(2), .node(3))])
        let box = placement.clusterFrames[0]
        XCTAssertTrue(inner(box).contains(frame(of: 1, in: placement)))
        XCTAssertTrue(inner(box).contains(frame(of: 2, in: placement)))
        XCTAssertFalse(box.intersects(frame(of: 0, in: placement)))
        XCTAssertFalse(box.intersects(frame(of: 3, in: placement)))
        XCTAssertTrue(CGRect(origin: .zero, size: placement.size).insetBy(dx: -accuracy, dy: -accuracy).contains(box))
    }

    func testNestedBoxesSitInsideEachOtherAndBoxesSideBySideDoNotOverlap() throws {
        // Cluster 1 is inside cluster 0; cluster 2 is beside them; node 5 is outside every box.
        let nodeClusters: [Int?] = [0, 1, 1, 2, 2, nil]
        let placement = try place(nodeClusters: nodeClusters, clusters: [cluster(), cluster(in: 0), cluster()],
                                  edges: [edge(.node(0), .node(1)), edge(.node(1), .node(2)), edge(.node(2), .node(3)), edge(.node(3), .node(4)),
                                          edge(.node(5), .node(4)), edge(.node(0), .node(5))])
        let frames = placement.clusterFrames
        XCTAssertTrue(inner(frames[0]).contains(frames[1]))
        XCTAssertFalse(frames[0].intersects(frames[2]))
        for (node, cluster) in nodeClusters.enumerated() {
            for (index, box) in frames.enumerated() {
                let holds = cluster == index || (index == 0 && cluster == 1)
                if holds { XCTAssertTrue(inner(box).contains(frame(of: node, in: placement)), "node \(node) in box \(index)") }
                else { XCTAssertFalse(box.intersects(frame(of: node, in: placement)), "node \(node) outside box \(index)") }
            }
        }
    }

    func testAnEdgeIntoABoxCrossesTheBorderFacingItsSource() throws {
        let placement = try place(nodeClusters: [nil, 0], clusters: [cluster()], edges: [edge(.node(0), .node(1))])
        let route = placement.edgeRoutes[0]
        XCTAssertEqual(route.points.first, placement.nodeCenters[0])
        XCTAssertEqual(route.points.last, placement.nodeCenters[1])
        let box = placement.clusterFrames[0]
        XCTAssertTrue(route.points.contains { point in abs(point.y - box.minY) < accuracy && point.x > box.minX && point.x < box.maxX })
        XCTAssertEqual(route.segmentsRunVertically.count, route.points.count - 1)
        // Inside the box the edge comes down from the border point, a border gap above the node's rank.
        XCTAssertEqual(frame(of: 1, in: placement).minY - (box.minY + padding.top), 20, accuracy: accuracy)
    }

    func testAnEdgeBackUpOutOfABoxLeavesThroughItsTop() throws {
        let placement = try place(nodeClusters: [nil, 0], clusters: [cluster()], edges: [edge(.node(0), .node(1)), edge(.node(1), .node(0))])
        let box = placement.clusterFrames[0]
        XCTAssertGreaterThan(placement.nodeCenters[1].y, placement.nodeCenters[0].y)
        let back = placement.edgeRoutes[1]
        XCTAssertTrue(back.points.contains { point in abs(point.y - box.minY) < accuracy })
        XCTAssertFalse(back.points.contains { point in abs(point.y - box.maxY) < accuracy })
    }

    func testABoxLaysItsNodesOutInItsOwnDirection() throws {
        let placement = try place(nodeClusters: [nil, 0, 0], clusters: [cluster(direction: .leftToRight)],
                                  edges: [edge(.node(1), .node(2)), edge(.node(0), .cluster(0))])
        XCTAssertGreaterThan(placement.nodeCenters[2].x, placement.nodeCenters[1].x)
        XCTAssertEqual(placement.nodeCenters[2].y, placement.nodeCenters[1].y, accuracy: accuracy)
        XCTAssertGreaterThan(placement.clusterFrames[0].minY, placement.nodeCenters[0].y)
    }

    func testAnEdgeToABoxItselfEndsAtTheBoxsCenter() throws {
        let placement = try place(nodeClusters: [nil, 0], clusters: [cluster()], edges: [edge(.node(0), .cluster(0))])
        let box = placement.clusterFrames[0]
        XCTAssertEqual(placement.edgeRoutes[0].points.last, CGPoint(x: box.midX, y: box.midY))
    }

    func testAnEdgeLeavingAcrossTheBoxsFlowPinsItsNodeFirstAndRunsStraightToTheBorder() throws {
        // A top-to-bottom diagram, a left-to-right box: nodes 1 and 2 share the box's first rank, and the edge from
        // node 0 above enters through the top, across the box's flow, straight down to node 2, which goes first.
        let placement = try place(nodeClusters: [nil, 0, 0, 0], clusters: [cluster(direction: .leftToRight)],
                                  edges: [edge(.node(1), .node(3)), edge(.node(2), .node(3)), edge(.node(0), .node(2))])
        XCTAssertEqual(placement.nodeCenters[1].x, placement.nodeCenters[2].x, accuracy: accuracy)
        XCTAssertLessThan(placement.nodeCenters[2].y, placement.nodeCenters[1].y)
        let route = placement.edgeRoutes[2]
        let box = placement.clusterFrames[0]
        let border = try XCTUnwrap(route.points.first { point in abs(point.y - box.minY) < accuracy })
        XCTAssertEqual(border.x, placement.nodeCenters[2].x, accuracy: accuracy)
        XCTAssertEqual(route.segmentsRunVertically.last, true)
    }

    func testTwoEdgesLeavingOneRankAcrossTheFlowAreRefused() {
        XCTAssertThrowsError(try place(nodeClusters: [nil, 0, 0, 0], clusters: [cluster(direction: .leftToRight)],
                                       edges: [edge(.node(1), .node(3)), edge(.node(2), .node(3)), edge(.node(0), .node(1)), edge(.node(0), .node(2))])) { error in
            XCTAssertEqual(error as? LayeredClusterLayoutError, .crossFlowExitsShareARank)
        }
    }

    func testAnEdgeBetweenABoxAndWhatItHoldsIsRefused() {
        for edges in [[edge(.node(0), .cluster(0))], [edge(.cluster(0), .cluster(1))], [edge(.cluster(1), .cluster(1))]] {
            XCTAssertThrowsError(try place(nodeClusters: [0, 1], clusters: [cluster(), cluster(in: 0)], edges: edges)) { error in
                XCTAssertEqual(error as? LayeredClusterLayoutError, .edgeIntoItsOwnCluster)
            }
        }
    }

    func testABoxInsideItselfIsRefused() {
        XCTAssertThrowsError(try place(nodeClusters: [0], clusters: [cluster(in: 1), cluster(in: 0)], edges: [])) { error in
            XCTAssertEqual(error as? LayeredClusterLayoutError, .clusterInsideItself)
        }
    }

    func testAnEmptyBoxTakesItsPaddingAndItsMinimumWidth() throws {
        let placement = try place(nodeClusters: [nil], clusters: [cluster(minimumWidth: 150)], edges: [edge(.node(0), .cluster(0))])
        XCTAssertEqual(placement.clusterFrames[0].size, CGSize(width: 150, height: padding.top + padding.bottom))
    }

    func testTheEndOutsideLinesUpWithWhereTheEdgeLeavesTheBox() throws {
        // Nodes 1 and 2 sit side by side in the box; node 3 below takes the edge from node 2.
        let placement = try place(nodeClusters: [0, 0, 0, nil], clusters: [cluster()],
                                  edges: [edge(.node(0), .node(1)), edge(.node(0), .node(2)), edge(.node(2), .node(3))])
        let box = placement.clusterFrames[0]
        let border = try XCTUnwrap(placement.edgeRoutes[2].points.first { point in abs(point.y - box.maxY) < accuracy })
        XCTAssertEqual(placement.nodeCenters[3].x, border.x, accuracy: 0.5)
        XCTAssertNotEqual(placement.nodeCenters[3].x, box.midX, accuracy: 1)
    }

    func testWithoutBoxesThePlacementIsTheLayeredLayouts() throws {
        let edges = [(0, 1), (0, 2), (1, 3), (2, 3), (3, 0)]
        let placement = try place(nodeClusters: [nil, nil, nil, nil], clusters: [],
                                  edges: edges.map { source, target in edge(.node(source), .node(target)) })
        let layered = try XCTUnwrap(LayeredLayout.place(LayeredGraph(nodeSizes: Array(repeating: LayeredSize(across: 60, along: 40), count: 4),
                                                                     edges: edges.map { source, target in
                                                                         LayeredEdge(source: source, target: target, minimumRankSpan: 1, labelSize: nil)
                                                                     }),
                                                        spacing: spacing, maximumPointCount: 1_000))
        XCTAssertEqual(placement.nodeCenters, layered.nodeCenters)
        XCTAssertEqual(placement.edgeRoutes.map(\.points), layered.edgeRoutes)
        XCTAssertEqual(placement.size, layered.extent)
    }

    func testThePointLimitCountsEveryBox() {
        XCTAssertThrowsError(try LayeredClusterLayout.place(LayeredClusterGraph(nodeSizes: Array(repeating: nodeSize, count: 4), nodeClusters: [0, 0, 1, 1],
                                                                                clusters: [cluster(), cluster()],
                                                                                edges: [edge(.node(0), .node(1)), edge(.node(2), .node(3))],
                                                                                direction: .topToBottom),
                                                            spacing: spacing, maximumPointCount: 5)) { error in
            XCTAssertEqual(error as? LayeredClusterLayoutError, .tooManyPoints)
        }
    }
}
