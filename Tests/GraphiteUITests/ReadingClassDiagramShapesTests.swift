import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingClassDiagramShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAClassDiagram: Error {}

    private func classDiagram(_ source: String) throws -> ReadingClassDiagram {
        guard case .classDiagram(let classDiagram) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsAClassDiagram()
        }
        return classDiagram
    }

    func testMembersStartAtTheBoxsPaddingWithTheirStyle() throws {
        let drawn = try classDiagram("classDiagram\nclass Shape {\n  +String name\n  +count()$ int\n  +area()* double\n}")
        let box = drawn.layout.classes[0].frame
        let lines = drawn.shapes.memberLines
        XCTAssertEqual(lines.map(\.text), ["+String name", "+count() : int", "+area() : double"])
        for line in lines { XCTAssertEqual(line.center.x - line.width / 2, box.minX + 12, accuracy: 0.01) }
        XCTAssertEqual(lines.map(\.isUnderlined), [false, true, false])
        XCTAssertEqual(lines.map(\.isItalic), [false, false, true])
        XCTAssertEqual(lines[0].font.size, 14)
    }

    func testTextIsSortedByHowItIsPainted() throws {
        let drawn = try classDiagram("---\ntitle: Plan\n---\nclassDiagram\nclass Shape <<interface>>\nShape \"1\" --> \"*\" Other : uses\nnote \"A note\"")
        XCTAssertEqual(drawn.shapes.nameLines.map(\.text), ["Shape", "Other"])
        XCTAssertTrue(drawn.shapes.nameLines.allSatisfy(\.isBold))
        XCTAssertEqual(drawn.shapes.annotationLines.map(\.text), ["«interface»"])
        XCTAssertEqual(drawn.shapes.cardinalityLines.map(\.text), ["1", "*"])
        XCTAssertEqual(drawn.shapes.cardinalityLines[0].font.size, 13)
        XCTAssertEqual(drawn.shapes.edgeTextLines.map(\.text), ["uses"])
        XCTAssertEqual(drawn.shapes.noteTextLines.map(\.text), ["A note", "Plan"])
        XCTAssertEqual(drawn.shapes.noteTextLines.last?.isBold, true)
    }

    func testTheShapesAreTheLayoutsBoxesNotesAndLines() throws {
        let drawn = try classDiagram("classDiagram\nA ..|> B\nnote for A \"Why\"")
        XCTAssertTrue(drawn.shapes.solidLines.isEmpty)
        XCTAssertFalse(drawn.shapes.dashedLines.isEmpty)
        XCTAssertFalse(drawn.shapes.dottedLines.isEmpty)
        XCTAssertFalse(drawn.shapes.strokedMarks.isEmpty)
        XCTAssertTrue(drawn.shapes.classFills.boundingRect.contains(drawn.layout.classes[1].frame.insetBy(dx: 1, dy: 1)))
        XCTAssertEqual(drawn.shapes.noteFills.boundingRect, drawn.layout.notes[0].frame)
    }
}
