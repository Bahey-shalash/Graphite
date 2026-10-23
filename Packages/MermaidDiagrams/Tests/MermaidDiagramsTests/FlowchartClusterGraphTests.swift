import XCTest
@testable import MermaidDiagrams

/// A flowchart's groups laid out as boxes (`FlowchartClusterGraph`, through `FlowchartLayoutEngine`): Pele's padding
/// and title band, nesting, a group's own direction, edges to a group and into it, and what is not laid out.
final class FlowchartClusterGraphTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ source: String) throws -> FlowchartLayout {
        try UniformWidthLayout.layout(source)
    }

    func testAGroupIsABoxAroundItsNodesWithItsTitleInABandAlongTheTop() throws {
        // "Group" is 40 points wide and 24 high; node "A" is 48 by 48.
        let laidOut = try layout("flowchart TD\nsubgraph one [Group]\nA --> B\nend\nC --> A")
        let box = try XCTUnwrap(laidOut.clusters.first)
        XCTAssertEqual(laidOut.clusters.count, 1)
        XCTAssertEqual(box.depth, 0)
        let nodeA = laidOut.nodes[0].frame
        let nodeB = laidOut.nodes[1].frame
        XCTAssertEqual(box.frame.width, 48 + 2 * 20, accuracy: accuracy)
        XCTAssertEqual(nodeB.maxY + 20, box.frame.maxY, accuracy: accuracy)
        XCTAssertGreaterThanOrEqual(nodeA.minY, box.frame.minY + 24 + 16 - accuracy)
        XCTAssertFalse(box.frame.intersects(laidOut.nodes[2].frame))
        let title = try XCTUnwrap(box.title)
        XCTAssertEqual(title.lines, ["Group"])
        XCTAssertEqual(title.center.y, box.frame.minY + 8 + 12, accuracy: accuracy)
        XCTAssertTrue(CGRect(origin: .zero, size: laidOut.size).contains(box.frame))
    }

    func testAGroupIsAtLeastAsWideAsItsTitleAndWithoutTitleHasPelesPaddingAbove() throws {
        let titled = try layout("flowchart TD\nsubgraph one [A title much wider than its node]\nA\nend")
        let title = try XCTUnwrap(titled.clusters[0].title)
        XCTAssertEqual(titled.clusters[0].frame.width, title.size.width + 2 * 20 - 12, accuracy: accuracy)
        let untitled = try layout("flowchart TD\nsubgraph\nA\nend")
        XCTAssertNil(untitled.clusters[0].title)
        XCTAssertEqual(untitled.nodes[0].frame.minY - untitled.clusters[0].frame.minY, 20, accuracy: accuracy)
    }

    func testNestedGroupsAreBoxesInsideBoxes() throws {
        let laidOut = try layout("flowchart TD\nsubgraph outer\nA --> B\nsubgraph inner\nC\nend\nend\nB --> C")
        XCTAssertEqual(laidOut.clusters.map(\.depth), [0, 1])
        XCTAssertTrue(laidOut.clusters[0].frame.insetBy(dx: 20 - accuracy, dy: 0).contains(laidOut.clusters[1].frame))
        XCTAssertTrue(laidOut.clusters[1].frame.contains(laidOut.nodes[2].frame))
        XCTAssertFalse(laidOut.clusters[1].frame.intersects(laidOut.nodes[0].frame))
    }

    func testAGroupRunsInItsOwnDirection() throws {
        let laidOut = try layout("flowchart TB\nsubgraph sideways\ndirection LR\nA --> B\nend")
        XCTAssertGreaterThan(laidOut.nodes[1].frame.minX, laidOut.nodes[0].frame.maxX)
        XCTAssertEqual(laidOut.nodes[1].frame.midY, laidOut.nodes[0].frame.midY, accuracy: accuracy)
        let arrow = try XCTUnwrap(laidOut.edges[0].targetMark)
        XCTAssertEqual(arrow.direction, CGVector(dx: 1, dy: 0))
    }

    func testANodeThatNamesAGroupIsItsBoxAndIsNotDrawn() throws {
        let laidOut = try layout("flowchart LR\nX --> one\nsubgraph one\nA\nend")
        XCTAssertEqual(laidOut.nodes.count, 2)
        let box = laidOut.clusters[0].frame
        let arrow = try XCTUnwrap(laidOut.edges[0].targetMark)
        XCTAssertEqual(arrow.tip.x, box.minX, accuracy: accuracy)
        XCTAssertEqual(arrow.direction, CGVector(dx: 1, dy: 0))
    }

    func testAnEdgeIntoAGroupCrossesItsTopAndEndsOnItsNode() throws {
        let laidOut = try layout("flowchart TD\nX --> A\nsubgraph S\nA\nend")
        let box = laidOut.clusters[0].frame
        let edge = laidOut.edges[0]
        XCTAssertTrue(edge.path.allPoints.contains { point in abs(point.y - box.minY) < accuracy })
        XCTAssertEqual(try XCTUnwrap(edge.targetMark).tip.y, laidOut.nodes[1].frame.minY, accuracy: accuracy)
    }

    func testAnEdgeThroughATitleMarksItCrossed() throws {
        let crossed = try layout("flowchart TD\nX --> A\nsubgraph S [A title as wide as the box]\nA\nend")
        XCTAssertTrue(crossed.clusters[0].isTitleCrossed)
        XCTAssertFalse(try layout("flowchart TD\nsubgraph S [Title]\nA\nend").clusters[0].isTitleCrossed)
    }

    func testAnEdgeToAGroupKeepsClearOfWhereAnotherLeavesIt() throws {
        // D --> E leaves the box "inner" through its bottom, under D; the edge from the box itself starts beside it.
        let laidOut = try layout("flowchart TD\nsubgraph inner\nD\nend\nD --> E\ninner --> F")
        let leaving = try XCTUnwrap(laidOut.edges[0].path.allPoints.first { point in abs(point.y - laidOut.clusters[0].frame.maxY) < accuracy })
        XCTAssertGreaterThanOrEqual(abs(laidOut.edges[1].path.start.x - leaving.x), FlowchartEdgePorts.portSeparation / 2 - accuracy)
    }

    func testWhatIsNotLaidOutKeepsTheBlockAsCode() {
        let sources = [
            "flowchart TD\nsubgraph one\nA --> B\nend\none@{ view: collapsed }",
            "flowchart TD\nsubgraph one\nA\nend\none --> one",
            "flowchart TD\nsubgraph one\nA\nend\nA --> one",
            "flowchart TB\nX --> A\nX --> B\nsubgraph S\ndirection LR\nA --> C\nB --> C\nend",
        ]
        for source in sources {
            XCTAssertThrowsError(try layout(source), source) { error in
                XCTAssertEqual(error as? FlowchartLayoutError, .subgraphsNotLaidOut, source)
            }
        }
    }

    func testTheLayoutPointLimitCountsTheBoxes() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumLayoutPointCount = 10
        XCTAssertThrowsError(try UniformWidthLayout.layout("flowchart TD\nsubgraph one\nA -----------------> B\nend", limits: limits)) { error in
            XCTAssertEqual(error as? FlowchartLayoutError, .tooManyLayoutPoints(limit: 10))
        }
    }
}
