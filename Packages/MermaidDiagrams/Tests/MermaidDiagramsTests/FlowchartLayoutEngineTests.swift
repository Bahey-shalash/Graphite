import XCTest
@testable import MermaidDiagrams

final class FlowchartLayoutEngineTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> FlowchartLayout {
        try UniformWidthLayout.layout(source, limits: limits)
    }

    func testAChainRunsDownOneRankGapApartAndStaysInLine() throws {
        let nodes = try layout("flowchart TD\nA --> B --> C").nodes
        XCTAssertEqual(nodes[1].frame.minY - nodes[0].frame.maxY, 48, accuracy: accuracy)
        XCTAssertEqual(nodes[2].frame.minY - nodes[1].frame.maxY, 48, accuracy: accuracy)
        XCTAssertEqual(nodes[0].frame.midX, nodes[2].frame.midX, accuracy: accuracy)
    }

    func testEachDirectionPlacesTheNextRankOnItsSide() throws {
        func secondFromFirst(_ header: String) throws -> CGVector {
            let nodes = try layout("\(header)\nA --> B").nodes
            return CGVector(dx: nodes[1].frame.midX - nodes[0].frame.midX, dy: nodes[1].frame.midY - nodes[0].frame.midY)
        }
        XCTAssertGreaterThan(try secondFromFirst("flowchart TB").dy, 0)
        XCTAssertLessThan(try secondFromFirst("flowchart BT").dy, 0)
        XCTAssertGreaterThan(try secondFromFirst("flowchart LR").dx, 0)
        XCTAssertLessThan(try secondFromFirst("flowchart RL").dx, 0)
        XCTAssertEqual(try secondFromFirst("flowchart LR").dy, 0, accuracy: accuracy)
    }

    func testSiblingsShareARankAtTheNodeGapAndTheirParentIsCenteredOverThem() throws {
        let nodes = try layout("flowchart TD\nA --> B\nA --> C").nodes
        XCTAssertEqual(nodes[1].frame.midY, nodes[2].frame.midY, accuracy: accuracy)
        XCTAssertEqual(abs(nodes[2].frame.minX - nodes[1].frame.maxX), 40, accuracy: accuracy)
        XCTAssertEqual(nodes[0].frame.midX, (nodes[1].frame.midX + nodes[2].frame.midX) / 2, accuracy: 1)
    }

    func testShapesTakePelesSizesAroundTheirText() throws {
        // Text "Done" is 4 × 8 = 32 points wide and 24 high.
        let nodes = try layout("flowchart TD\nA[Done]\nB{Done}\nC((Done))\nD([Done])").nodes
        XCTAssertEqual(nodes[0].frame.size, CGSize(width: 32 + 36, height: 24 + 24))
        XCTAssertEqual(nodes[1].frame.width, (32 + 16) + 1.6 * (24 + 8), accuracy: accuracy)
        XCTAssertEqual(nodes[1].frame.height, (32 + 16) / 1.6 + (24 + 8), accuracy: accuracy)
        XCTAssertEqual(nodes[2].frame.width, max((32 * 32 + 24 * 24).squareRoot() + 16, 44), accuracy: accuracy)
        XCTAssertEqual(nodes[3].frame.width, 32 + 48 * 0.5 + 36 - 8, accuracy: accuracy)
    }

    func testAnEdgeRunsFromItsSourcesOutlineToItsArrowOnTheTargetsOutline() throws {
        let laidOut = try layout("flowchart TD\nA --> B")
        let edge = try XCTUnwrap(laidOut.edges.first)
        XCTAssertEqual(edge.path.start.y, laidOut.nodes[0].frame.maxY, accuracy: accuracy)
        let mark = try XCTUnwrap(edge.targetMark)
        XCTAssertEqual(mark.tip.y, laidOut.nodes[1].frame.minY, accuracy: accuracy)
        XCTAssertEqual(mark.direction, CGVector(dx: 0, dy: 1))
        XCTAssertEqual(edge.path.allPoints.last?.y ?? 0, mark.tip.y - DiagramEdgeMark.lineTrim(for: .arrow), accuracy: accuracy)
        XCTAssertNil(edge.sourceMark)
    }

    func testEdgesMeetADiamondOnItsOutline() throws {
        let laidOut = try layout("flowchart TD\nA{Decide} --> B\nA --> C")
        let diamond = laidOut.nodes[0].frame
        for edge in laidOut.edges {
            let start = edge.path.start
            // On the lower half of the outline: |x| / (w / 2) + |y| / (h / 2) = 1.
            let onOutline = abs(start.x - diamond.midX) / (diamond.width / 2) + abs(start.y - diamond.midY) / (diamond.height / 2)
            XCTAssertEqual(onOutline, 1, accuracy: 0.01)
            XCTAssertGreaterThan(start.y, diamond.midY)
        }
    }

    func testEdgesMeetingOneSideSpreadAlongItInTheOrderOfTheirOtherEnds() throws {
        let laidOut = try layout("flowchart TD\nA[A wide source node] --> B & C & D")
        let starts = laidOut.edges.map(\.path.start.x)
        let targets = laidOut.edges.map { edge in edge.targetMark?.tip.x ?? 0 }
        XCTAssertEqual(Set(starts.map { start in Int(start.rounded()) }).count, 3)
        XCTAssertEqual(starts.indices.sorted { starts[$0] < starts[$1] }, targets.indices.sorted { targets[$0] < targets[$1] })
        XCTAssertEqual(starts.max()! - starts.min()!, 2 * FlowchartEdgePorts.portSeparation, accuracy: accuracy)
    }

    func testAnEdgesTextTakesAPlaceBetweenTheRanks() throws {
        let laidOut = try layout("flowchart TD\nA -->|Yes| B")
        let text = try XCTUnwrap(laidOut.edges.first?.text)
        XCTAssertEqual(text.lines, ["Yes"])
        XCTAssertGreaterThan(text.frame.minY, laidOut.nodes[0].frame.maxY)
        XCTAssertLessThan(text.frame.maxY, laidOut.nodes[1].frame.minY)
        // Half a rank gap, the text's place (21 high and 4 of room), half a rank gap.
        XCTAssertEqual(laidOut.nodes[1].frame.minY - laidOut.nodes[0].frame.maxY, 24 + 25 + 24, accuracy: accuracy)
    }

    func testAnEdgeThatClosesACycleRunsBackUpToItsTarget() throws {
        let laidOut = try layout("flowchart TD\nA --> B\nB --> A")
        let back = laidOut.edges[1]
        let mark = try XCTUnwrap(back.targetMark)
        XCTAssertEqual(mark.tip.y, laidOut.nodes[0].frame.maxY, accuracy: accuracy)
        XCTAssertEqual(mark.direction.dy, -1)
        XCTAssertEqual(back.path.start.y, laidOut.nodes[1].frame.minY, accuracy: accuracy)
    }

    func testAnEdgeToItsOwnNodeLoopsBesideItWithinTheDrawing() throws {
        let laidOut = try layout("flowchart TD\nA --> A")
        let loop = laidOut.edges[0]
        let node = laidOut.nodes[0].frame
        XCTAssertTrue(loop.path.allPoints.allSatisfy { point in point.x >= node.maxX - accuracy })
        XCTAssertNotNil(loop.targetMark)
        XCTAssertLessThanOrEqual(loop.path.allPoints.map(\.x).max() ?? 0, laidOut.size.width)
    }

    func testNoTwoNodesOverlapAndEverythingIsInsideThePadding() throws {
        let laidOut = try layout("""
        flowchart TD
          A --> B & C & D & E
          B & C --> F
          D & E -->|long text that wraps beyond the wrapping width of two hundred points| G
          F & G --> H
          A ---> H
          H --> A
          C -.-> C
        """)
        let frames = laidOut.nodes.map(\.frame)
        for (index, frame) in frames.enumerated() {
            for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other), "\(frame) and \(other)") }
            XCTAssertTrue(CGRect(origin: .zero, size: laidOut.size).insetBy(dx: 8 - accuracy, dy: 8 - accuracy).contains(frame))
        }
        let wrapped = try XCTUnwrap(laidOut.edges.compactMap(\.text).first)
        XCTAssertGreaterThan(wrapped.lines.count, 1)
        XCTAssertTrue(wrapped.lineWidths.allSatisfy { width in width <= 200 })
    }

    func testTheTitleIsCenteredAboveTheDiagram() throws {
        let laidOut = try layout("---\ntitle: A title wider than the diagram itself\n---\nflowchart TD\nA --> B")
        let title = try XCTUnwrap(laidOut.title)
        XCTAssertEqual(title.center.x, laidOut.size.width / 2, accuracy: accuracy)
        XCTAssertLessThan(title.frame.maxY, laidOut.nodes[0].frame.minY)
        XCTAssertEqual(laidOut.nodes[0].frame.midX, laidOut.size.width / 2, accuracy: 1)
    }

    func testAFlowchartWithGroupsIsLaidOutInBoxesAndOneWithoutHasNone() throws {
        let grouped = try layout("flowchart TD\nsubgraph one\nA\nend")
        XCTAssertEqual(grouped.clusters.count, 1)
        XCTAssertTrue(grouped.clusters[0].frame.contains(grouped.nodes[0].frame))
        XCTAssertEqual(try layout("flowchart TD\nA --> B").clusters, [])
    }

    func testAnEdgeSpanningMoreRanksThanTheLimitAllowsIsRefused() throws {
        var limits = MermaidDiagramLimits.standard
        limits.maximumLayoutPointCount = 10
        XCTAssertThrowsError(try layout("flowchart TD\nA -----------------> B", limits: limits)) { error in
            XCTAssertEqual(error as? FlowchartLayoutError, .tooManyLayoutPoints(limit: 10))
        }
    }

    func testAnInvisibleEdgePlacesItsNodesWithoutMarks() throws {
        let laidOut = try layout("flowchart LR\nA ~~~ B")
        XCTAssertGreaterThan(laidOut.nodes[1].frame.minX, laidOut.nodes[0].frame.maxX)
        XCTAssertNil(laidOut.edges[0].targetMark)
        XCTAssertEqual(laidOut.edges[0].stroke, .invisible)
    }
}
