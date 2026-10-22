import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingFlowchartShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAFlowchart: Error {}

    private func flowchart(_ source: String) throws -> ReadingFlowchart {
        guard case .flowchart(let flowchart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsAFlowchart()
        }
        return flowchart
    }

    func testEachLineOfTextIsCenteredOnItsLineOfTheBlock() throws {
        let flowchart = try flowchart("flowchart TD\nA[one<br>two] -->|label| B")
        let nodeText = flowchart.layout.nodes[0].text
        let lines = flowchart.shapes.nodeTextLines.filter { line in line.text == "one" || line.text == "two" }
        XCTAssertEqual(lines.map(\.text), ["one", "two"])
        XCTAssertEqual(lines[0].center.x, nodeText.center.x)
        XCTAssertEqual(lines[1].center.y - lines[0].center.y, nodeText.lineHeight)
        XCTAssertEqual(lines[0].center.y, nodeText.center.y - nodeText.lineHeight / 2, accuracy: 0.01)
        XCTAssertEqual(flowchart.shapes.edgeTextLines.map(\.text), ["label"])
        XCTAssertEqual(flowchart.shapes.edgeTextLines[0].font.size, 14)
    }

    func testTheTitleIsTheLastLineAndBold() throws {
        let flowchart = try flowchart("---\ntitle: Plan\n---\nflowchart LR\nA --> B")
        XCTAssertEqual(flowchart.shapes.nodeTextLines.last?.text, "Plan")
        XCTAssertEqual(flowchart.shapes.nodeTextLines.last?.isBold, true)
    }

    func testGroupsArePaintedAsBoxesWithTheirTitles() throws {
        let flowchart = try flowchart("flowchart TD\nsubgraph outer [Outer]\nA\nsubgraph inner [Inner]\nB\nend\nend")
        let clusters = flowchart.shapes.clusters
        XCTAssertEqual(clusters.fillsByDepth.count, 2)
        XCTAssertEqual(clusters.fillsByDepth[1].boundingRect.width, flowchart.layout.clusters[1].frame.width, accuracy: 0.01)
        XCTAssertFalse(clusters.outlines.isEmpty)
        XCTAssertEqual(clusters.titleLines.map(\.text), ["Outer", "Inner"])
        XCTAssertTrue(clusters.crossedTitleLines.isEmpty)
        let crossed = try self.flowchart("flowchart TD\nX --> A\nsubgraph S [A title as wide as its box]\nA\nend").shapes.clusters
        XCTAssertEqual(crossed.crossedTitleLines.map(\.text), ["A title as wide as its box"])
        XCTAssertFalse(crossed.crossedTitlePatchesByDepth[0].isEmpty)
    }

    func testTheShapesAreTheLayoutsOutlinesAndLines() throws {
        let flowchart = try flowchart("flowchart TD\nA ==> B\nB -.-> C")
        XCTAssertFalse(flowchart.shapes.nodeFills.isEmpty)
        XCTAssertFalse(flowchart.shapes.thickEdges.isEmpty)
        XCTAssertFalse(flowchart.shapes.dottedEdges.isEmpty)
        XCTAssertTrue(flowchart.shapes.solidEdges.isEmpty)
        XCTAssertTrue(flowchart.shapes.nodeFills.boundingRect.contains(flowchart.layout.nodes[1].frame.insetBy(dx: 1, dy: 1)))
    }
}
