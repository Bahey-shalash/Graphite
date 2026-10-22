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

    func testTheShapesAreTheLayoutsOutlinesAndLines() throws {
        let flowchart = try flowchart("flowchart TD\nA ==> B\nB -.-> C")
        XCTAssertFalse(flowchart.shapes.nodeFills.isEmpty)
        XCTAssertFalse(flowchart.shapes.thickEdges.isEmpty)
        XCTAssertFalse(flowchart.shapes.dottedEdges.isEmpty)
        XCTAssertTrue(flowchart.shapes.solidEdges.isEmpty)
        XCTAssertTrue(flowchart.shapes.nodeFills.boundingRect.contains(flowchart.layout.nodes[1].frame.insetBy(dx: 1, dy: 1)))
    }
}
