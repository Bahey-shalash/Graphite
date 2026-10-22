import XCTest
@testable import MermaidDiagrams

final class StateDiagramDrawingPartsTests: XCTestCase {
    private func parts(_ source: String) throws -> StateDiagramDrawingParts {
        StateDiagramDrawingParts(layout: try StateDiagramUniformLayout.layout(source))
    }

    private func subpathCount(_ path: CGPath) -> Int {
        var count = 0
        path.applyWithBlock { element in
            if element.pointee.type == .moveToPoint { count += 1 }
        }
        return count
    }

    func testEachKindOfStateGoesToTheWayItIsPainted() throws {
        let drawn = try parts("stateDiagram-v2\nstate pick <<choice>>\nstate split <<fork>>\n[*] --> split\nsplit --> pick\npick --> A\nA --> [*]")
        XCTAssertEqual(subpathCount(drawn.stateFills), 2, "A box and a diamond")
        XCTAssertEqual(subpathCount(drawn.stateOutlines), 2)
        XCTAssertEqual(subpathCount(drawn.endRings), 1)
        XCTAssertEqual(subpathCount(drawn.solidMarks), 3, "The start, the end's dot and the bar")
        XCTAssertEqual(drawn.stateTexts.map(\.lines), [["A"]])
    }

    func testABoxWithSeveralDescriptionsHasALineUnderItsName() throws {
        let plain = try parts("stateDiagram-v2\nA : one")
        XCTAssertEqual(subpathCount(plain.stateOutlines), 1)
        let detailed = try parts("stateDiagram-v2\nA : one\nA : two")
        XCTAssertEqual(subpathCount(detailed.stateOutlines), 2)
        XCTAssertEqual(detailed.stateTexts.map(\.lines), [["one"], ["two"]])
    }

    func testTransitionsHaveLinesArrowsAndPatchesBehindTheirText() throws {
        let layout = try StateDiagramUniformLayout.layout("stateDiagram-v2\nA --> B : go\nB --> A")
        let drawn = StateDiagramDrawingParts(layout: layout)
        XCTAssertEqual(subpathCount(drawn.transitionLines), 2)
        XCTAssertEqual(subpathCount(drawn.arrows), 2)
        let text = try XCTUnwrap(layout.transitions[0].text)
        XCTAssertEqual(drawn.transitionTexts, [text])
        XCTAssertEqual(drawn.transitionTextPatches.boundingBoxOfPath.width, text.frame.width + 8, accuracy: 0.01)
    }

    func testNotesHaveSheetsFoldsAndLinesToTheirState() throws {
        let layout = try StateDiagramUniformLayout.layout("stateDiagram-v2\nA\nnote left of A : one\nnote right of A : two")
        let drawn = StateDiagramDrawingParts(layout: layout)
        XCTAssertEqual(subpathCount(drawn.noteSheets), 2)
        XCTAssertEqual(subpathCount(drawn.noteFolds), 2)
        XCTAssertEqual(subpathCount(drawn.noteConnectors), 2)
        XCTAssertEqual(drawn.noteTexts.map(\.lines), [["one"], ["two"]])
        XCTAssertTrue(drawn.transitionLines.isEmpty)
    }

    func testTheTitleIsAPartOfItsOwn() throws {
        XCTAssertEqual(try parts("---\ntitle: Machine\n---\nstateDiagram-v2\nA").title?.lines, ["Machine"])
    }
}
