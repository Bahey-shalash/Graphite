import XCTest
@testable import MermaidDiagrams

/// The cases of Pele's own Sankey layout tests (`tests/sankey/layout.test.ts`): a chart of 600 by 400 points, nodes
/// 10 points wide and 12 apart, in justified columns unless an alignment is given.
final class SankeyPlacementTests: XCTestCase {
    private func placed(_ rows: String, nodePadding: Double = 12, labelHeight: Double = 0,
                        alignment: SankeyNodeAlignment = .justify) throws -> (SankeyDiagram, SankeyPlacement) {
        let diagram = try SankeyReading.diagram("sankey\n" + rows)
        let options = SankeyPlacement.Options(width: 600, height: 400, nodeWidth: 10, nodePadding: nodePadding, labelHeight: labelHeight,
                                              alignment: alignment)
        return (diagram, try SankeyPlacement(diagram: diagram, options: options))
    }

    private func layers(_ rows: String, alignment: SankeyNodeAlignment = .justify) throws -> [String: Int] {
        let (diagram, placement) = try placed(rows, alignment: alignment)
        return Dictionary(uniqueKeysWithValues: zip(diagram.nodes.map(\.name), placement.nodes.map(\.layer)))
    }

    /// a → b → c → d, with a late source x → d and an early sink a → y.
    private let shape = "a,b,4\nb,c,3\nc,d,3\nx,d,2\na,y,1"

    func testEachNodeIsInTheColumnOfItsLongestDistanceFromASourceAndSinksAreLast() throws {
        XCTAssertEqual(try layers(shape), ["a": 0, "b": 1, "c": 2, "d": 3, "x": 0, "y": 3])
        XCTAssertEqual(try layers("a,b,1\nb,c,1\na,c,1"), ["a": 0, "b": 1, "c": 2])
    }

    func testTheFourAlignmentsPutNodesInTheirColumns() throws {
        XCTAssertEqual(try layers(shape, alignment: .left), ["a": 0, "b": 1, "c": 2, "d": 3, "x": 0, "y": 1])
        XCTAssertEqual(try layers("a,b,1\nb,c,1\na,c,1", alignment: .left), ["a": 0, "b": 1, "c": 2])
        XCTAssertEqual(try layers(shape, alignment: .right), ["a": 0, "b": 1, "c": 2, "d": 3, "x": 2, "y": 3])
        XCTAssertEqual(try layers(shape, alignment: .center), ["a": 0, "b": 1, "c": 2, "d": 3, "x": 2, "y": 1])
    }

    func testTheColumnsSpreadOverTheWidth() throws {
        let (_, placement) = try placed(shape)
        XCTAssertEqual(placement.nodes[0].x, 0)
        XCTAssertEqual(placement.nodes[3].x, 590)
        XCTAssertEqual(placement.nodes[1].x, 590 / 3, accuracy: 1e-6)
    }

    func testNodesAndBandsAreSizedByTheirFlow() throws {
        let (_, placement) = try placed("a,b,30\na,c,10\nb,d,30")
        let nodes = placement.nodes
        XCTAssertEqual(nodes[0].value, 40)
        XCTAssertEqual(nodes[0].height, 388, accuracy: 1e-6, "The second column holds two nodes and a gap, and sets the scale")
        XCTAssertEqual(nodes[1].height / nodes[2].height, 3, accuracy: 1e-6)
        XCTAssertEqual(placement.links[0].thickness / placement.links[1].thickness, 3, accuracy: 1e-6)
        XCTAssertEqual(placement.links[0].thickness + placement.links[1].thickness, nodes[0].height, accuracy: 1e-6)
    }

    func testANodesValueIsTheLargerOfWhatEntersAndWhatLeaves() throws {
        let (_, placement) = try placed("a,b,5\nb,c,2")
        XCTAssertEqual(placement.nodes[1].value, 5)
        XCTAssertGreaterThan(placement.nodes[1].height, placement.nodes[2].height)
    }

    func testAColumnsNodesStayApartAndInsideTheHeight() throws {
        let rows = (0..<12).map { index in "s\(index % 4),t\(index),\(1 + index % 5)" }.joined(separator: "\n")
        let (_, placement) = try placed(rows)
        for column in placement.columns {
            let nodes = column.map { node in placement.nodes[node] }.sorted { first, second in first.y < second.y }
            XCTAssertGreaterThanOrEqual(nodes[0].y, -1e-6)
            for (upper, lower) in zip(nodes, nodes.dropFirst()) { XCTAssertGreaterThanOrEqual(lower.y - (upper.y + upper.height), 12 - 1e-6) }
            XCTAssertLessThanOrEqual((nodes.last?.y ?? 0) + (nodes.last?.height ?? 0), 400 + 1e-6)
        }
    }

    func testBandsAreStackedOnANodeInTheOrderOfTheirOtherEndsAndInsideIt() throws {
        let (_, placement) = try placed("a,x,1\na,y,2\na,z,3\nb,z,1")
        let nodes = placement.nodes
        let leaving = placement.links.filter { link in link.source == 0 }.sorted { first, second in first.sourceY < second.sourceY }
        let targetTops = leaving.map { link in nodes[link.target].y }
        XCTAssertEqual(targetTops, targetTops.sorted())
        for link in placement.links {
            XCTAssertGreaterThanOrEqual(link.sourceY - link.thickness / 2, nodes[link.source].y - 1e-6)
            XCTAssertLessThanOrEqual(link.sourceY + link.thickness / 2, nodes[link.source].y + nodes[link.source].height + 1e-6)
            XCTAssertGreaterThanOrEqual(link.targetY - link.thickness / 2, nodes[link.target].y - 1e-6)
            XCTAssertLessThanOrEqual(link.targetY + link.thickness / 2, nodes[link.target].y + nodes[link.target].height + 1e-6)
        }
    }

    func testAColumnIsReorderedSoThatBandsDoNotCrossWhenTheyNeedNot() throws {
        let (_, placement) = try placed("a,low,1\nb,high,1\nroot,high,0.1\nroot,low,0.1")
        let nodes = placement.nodes
        let (first, second) = (placement.links[0], placement.links[1])
        XCTAssertEqual((nodes[first.source].y - nodes[second.source].y).sign, (nodes[first.target].y - nodes[second.target].y).sign)
    }

    func testThinNodesKeepRoomForTheirLabelsWhenTheColumnCanAffordIt() throws {
        let rows = "big,t,1000\n" + (0..<8).map { index in "thin\(index),t,1" }.joined(separator: "\n")
        let (_, roomy) = try placed(rows, nodePadding: 2, labelHeight: 16)
        let middles = ([roomy.nodes[0]] + roomy.nodes.dropFirst(2)).map { node in node.y + node.height / 2 }.sorted()
        for (upper, lower) in zip(middles, middles.dropFirst()) { XCTAssertGreaterThanOrEqual(lower - upper, 16 - 1e-6) }
        let many = (0..<100).map { index in "n\(index),t,1" }.joined(separator: "\n")
        XCTAssertTrue(try placed(many, labelHeight: 16).1.nodes.allSatisfy { node in node.y >= -1e-6 && node.y <= 400 },
                      "With more thin nodes than labels fit, the plain gaps are kept")
    }

    func testCircularLinksAreRefused() {
        for rows in ["a,a,1", "a,b,1\nb,a,1", "s,a,1\na,b,1\nb,c,1\nc,a,1\nc,tail,1"] {
            XCTAssertThrowsError(try placed(rows), rows) { error in XCTAssertEqual(error as? SankeyLayoutError, .circularLinks) }
        }
    }

    func testValuesThatAreNotNumbersAboveZeroAreNoFlowAndEverythingStaysFinite() throws {
        let (_, placement) = try placed("a,b,abc\na,c,-5\na,d,Infinity\nb,e,0\nx,y,1e308\nx,z,1e308")
        for node in placement.nodes { XCTAssertTrue([node.x, node.y, node.height].allSatisfy(\.isFinite)) }
        for link in placement.links { XCTAssertTrue([link.thickness, link.sourceY, link.targetY].allSatisfy(\.isFinite)) }
        XCTAssertEqual(placement.nodes[0].value, 0)
        XCTAssertEqual(placement.nodes[0].height, 0)
    }

    func testThePlacementIsTheSameEachTime() throws {
        let first = try placed(shape).1
        let second = try placed(shape).1
        XCTAssertEqual(first.nodes.map(\.y), second.nodes.map(\.y))
        XCTAssertEqual(first.links.map(\.sourceY), second.links.map(\.sourceY))
    }
}
