import XCTest
@testable import MermaidDiagrams

final class FlowchartDrawingPartsTests: XCTestCase {
    private func parts(_ source: String) throws -> FlowchartDrawingParts {
        FlowchartDrawingParts(layout: try UniformWidthLayout.layout(source))
    }

    func testEachStrokeGoesToItsOwnPath() throws {
        let drawn = try parts("flowchart TD\nA --> B\nB ==> C\nC -.-> D")
        XCTAssertFalse(drawn.solidEdges.isEmpty)
        XCTAssertFalse(drawn.thickEdges.isEmpty)
        XCTAssertFalse(drawn.dottedEdges.isEmpty)
        XCTAssertFalse(drawn.filledMarks.isEmpty)
        XCTAssertTrue(drawn.strokedMarks.isEmpty)
    }

    func testAnInvisibleEdgeHasNoLineAndNoMark() throws {
        let drawn = try parts("flowchart TD\nA ~~~ B")
        XCTAssertTrue(drawn.solidEdges.isEmpty && drawn.thickEdges.isEmpty && drawn.dottedEdges.isEmpty)
        XCTAssertTrue(drawn.filledMarks.isEmpty && drawn.strokedMarks.isEmpty)
    }

    func testCrossesAreStrokedAndCirclesFilled() throws {
        let drawn = try parts("flowchart LR\nA --x B\nB --o C")
        XCTAssertFalse(drawn.strokedMarks.isEmpty)
        XCTAssertFalse(drawn.filledMarks.isEmpty)
    }

    func testEdgeTextGetsAPatchSlightlyWiderThanItself() throws {
        let layout = try UniformWidthLayout.layout("flowchart TD\nA -->|Yes| B")
        let drawn = FlowchartDrawingParts(layout: layout)
        let text = try XCTUnwrap(layout.edges[0].text)
        XCTAssertEqual(drawn.edgeTexts, [text])
        XCTAssertEqual(drawn.edgeTextPatches.boundingBoxOfPath.width, text.frame.width + 8, accuracy: 0.01)
    }

    func testBareTextHasNoOutlineAndASubroutineItsInnerLines() throws {
        let bare = try parts("flowchart TD\nA@{ shape: text, label: \"Only text\" }")
        XCTAssertTrue(bare.nodeFills.isEmpty)
        XCTAssertEqual(bare.nodeTexts.first?.lines, ["Only text"])
        let subroutine = try parts("flowchart TD\nA[[Call]]")
        XCTAssertGreaterThan(subroutine.nodeOutlines.boundingBoxOfPath.width, 0)
    }
}
