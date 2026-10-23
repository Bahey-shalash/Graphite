import XCTest
@testable import MermaidDiagrams

final class ClassDiagramDrawingPartsTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func parts(_ body: String) throws -> (ClassDiagramDrawingParts, ClassDiagramLayout) {
        let layout = try ClassDiagramLayoutEngine.layout(ClassDiagramReading.classDiagram("classDiagram\n" + body), typography: typography, limits: .standard)
        return (ClassDiagramDrawingParts(layout: layout), layout)
    }

    func testLinesAreGroupedByTheirStyle() throws {
        let (solid, _) = try parts("A --> B")
        XCTAssertFalse(solid.solidLines.isEmpty)
        XCTAssertTrue(solid.dashedLines.isEmpty)
        XCTAssertTrue(solid.dottedLines.isEmpty)
        let (dashed, _) = try parts("A ..|> B\nnote for A \"Why\"")
        XCTAssertTrue(dashed.solidLines.isEmpty)
        XCTAssertFalse(dashed.dashedLines.isEmpty)
        XCTAssertFalse(dashed.dottedLines.isEmpty)
    }

    func testMarksAreFilledOrStrokedByTheirKind() throws {
        let (hollow, _) = try parts("A <|-- B\nC o-- D\nE ()--() F")
        XCTAssertTrue(hollow.filledMarks.isEmpty)
        XCTAssertFalse(hollow.strokedMarks.isEmpty)
        let (composition, layout) = try parts("A *-- B")
        let tip = try XCTUnwrap(layout.relations.first?.sourceMark?.tip)
        XCTAssertTrue(composition.filledMarks.boundingBoxOfPath.insetBy(dx: -1, dy: -1).contains(tip))
        XCTAssertEqual(composition.filledMarks.boundingBoxOfPath, composition.strokedMarks.boundingBoxOfPath)
        let (arrow, _) = try parts("A --> B")
        XCTAssertFalse(arrow.filledMarks.isEmpty)
        XCTAssertTrue(arrow.strokedMarks.isEmpty)
    }

    func testTextIsSortedByHowItIsPainted() throws {
        let (painted, layout) = try parts("""
        class Shape <<interface>> {
          +count()$ int
          +area()*
          +name
        }
        Shape "1" --> "*" Other : uses
        note "A note"
        bar ()-- Shape
        """)
        XCTAssertEqual(painted.names.map(\.lines), [["Shape"], ["Other"]])
        XCTAssertEqual(painted.annotations.map(\.lines), [["«interface»"]])
        XCTAssertEqual(painted.cardinalities.map(\.lines), [["1"], ["*"]])
        XCTAssertEqual(painted.edgeTexts.map(\.lines), [["uses"]])
        XCTAssertEqual(painted.noteTexts.map(\.lines), [["A note"], ["bar"]])
        XCTAssertEqual(painted.members.map(\.classifier), [.plain, .static, .abstract])
        let staticLine = layout.classes[0].members[1].text.frame
        XCTAssertEqual(painted.memberUnderlines.boundingBoxOfPath.minX, staticLine.minX, accuracy: 0.01)
        XCTAssertEqual(painted.memberUnderlines.boundingBoxOfPath.width, staticLine.width, accuracy: 0.01)
        XCTAssertFalse(painted.edgeTextPatches.isEmpty)
    }

    func testBoxesAndNotesFillTheirFrames() throws {
        let (painted, layout) = try parts("class A\nnote \"Hello\"")
        XCTAssertEqual(painted.classFills.boundingBoxOfPath, layout.classes[0].frame)
        XCTAssertEqual(painted.noteFills.boundingBoxOfPath, layout.notes[0].frame)
        XCTAssertEqual(painted.outlines.boundingBoxOfPath, layout.classes[0].frame.union(layout.notes[0].frame))
        XCTAssertNil(painted.title)
    }
}
