import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingStateDiagramShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAStateDiagram: Error {}

    private func stateDiagram(_ source: String) throws -> ReadingStateDiagram {
        guard case .stateDiagram(let diagram) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsAStateDiagram()
        }
        return diagram
    }

    func testEachLineOfTextIsCenteredOnItsLineOfTheBlock() throws {
        let diagram = try stateDiagram("stateDiagram-v2\nA : one<br>two\nA --> B : go")
        let name = try XCTUnwrap(diagram.layout.states[0].name)
        let lines = diagram.shapes.stateTextLines.filter { line in line.text == "one" || line.text == "two" }
        XCTAssertEqual(lines.map(\.text), ["one", "two"])
        XCTAssertEqual(lines[0].center.x, name.center.x)
        XCTAssertEqual(lines[1].center.y - lines[0].center.y, name.lineHeight)
        XCTAssertEqual(diagram.shapes.transitionTextLines.map(\.text), ["go"])
        XCTAssertEqual(diagram.shapes.transitionTextLines[0].font.size, 14)
    }

    func testNotesHaveTheirOwnTextAndShapes() throws {
        let diagram = try stateDiagram("stateDiagram-v2\nA\nnote right of A : an aside")
        XCTAssertEqual(diagram.shapes.noteTextLines.map(\.text), ["an aside"])
        XCTAssertFalse(diagram.shapes.noteSheets.isEmpty)
        XCTAssertFalse(diagram.shapes.noteFolds.isEmpty)
        XCTAssertFalse(diagram.shapes.noteConnectors.isEmpty)
        XCTAssertTrue(diagram.shapes.noteSheets.boundingRect.contains(diagram.layout.notes[0].frame.insetBy(dx: 1, dy: 1)))
    }

    func testTheTitleIsTheLastStateLineAndBold() throws {
        let diagram = try stateDiagram("---\ntitle: Plan\n---\nstateDiagram-v2\nA --> B")
        XCTAssertEqual(diagram.shapes.stateTextLines.last?.text, "Plan")
        XCTAssertEqual(diagram.shapes.stateTextLines.last?.isBold, true)
    }

    func testStartsEndsAndBarsAreSolidAndBoxesFilled() throws {
        let diagram = try stateDiagram("stateDiagram-v2\nstate split <<fork>>\n[*] --> split\nsplit --> A\nA --> [*]")
        XCTAssertFalse(diagram.shapes.solidMarks.isEmpty)
        XCTAssertFalse(diagram.shapes.endRings.isEmpty)
        XCTAssertFalse(diagram.shapes.arrows.isEmpty)
        let box = try XCTUnwrap(diagram.layout.states.first { state in state.kind == .state }?.frame)
        XCTAssertTrue(diagram.shapes.stateFills.boundingRect.contains(box.insetBy(dx: 1, dy: 1)))
    }
}
