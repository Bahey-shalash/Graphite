import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingEntityRelationshipShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAnEntityRelationshipDiagram: Error {}

    private func drawn(_ source: String) throws -> ReadingEntityRelationshipDiagram {
        guard case .entityRelationship(let diagram) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsAnEntityRelationshipDiagram()
        }
        return diagram
    }

    func testNamesAreTextTypesKeysAndCommentsMutedAndLabelsTheirOwn() throws {
        let diagram = try drawn("erDiagram\nCUSTOMER ||--o{ ORDER : places\nCUSTOMER {\n string name PK \"The key\"\n}")
        XCTAssertEqual(diagram.shapes.textLines.map(\.text), ["CUSTOMER", "name", "ORDER"])
        XCTAssertEqual(diagram.shapes.mutedLines.map(\.text), ["string", "PK", "The key"])
        XCTAssertEqual(diagram.shapes.mutedLines[1].font.size, 12)
        XCTAssertEqual(diagram.shapes.labelLines.map(\.text), ["places"])
        XCTAssertEqual(diagram.shapes.labelLines[0].font.size, 14)
    }

    func testEachCellLineStartsAtItsColumn() throws {
        let diagram = try drawn("erDiagram\nCUSTOMER {\n string name\n int age\n}")
        let rows = diagram.layout.entities[0].rows
        let types = diagram.shapes.mutedLines
        XCTAssertEqual(types.map(\.text), ["string", "int"])
        let typeTexts = rows.flatMap(\.texts).filter { cell in cell.column == .type }.map(\.text)
        XCTAssertEqual(types[0].center.x - typeTexts[0].size.width / 2, types[1].center.x - typeTexts[1].size.width / 2, accuracy: 0.01)
        XCTAssertEqual(types[0].center.y, typeTexts[0].center.y, accuracy: 0.01)
    }

    func testTheTitleIsTheLastLineAndBold() throws {
        let diagram = try drawn("---\ntitle: Orders\n---\nerDiagram\nA")
        XCTAssertEqual(diagram.shapes.textLines.last?.text, "Orders")
        XCTAssertEqual(diagram.shapes.textLines.last?.isBold, true)
    }

    func testTheShapesAreTheLayoutsLinesMarksAndBoxes() throws {
        let diagram = try drawn("erDiagram\nA ||--o{ B : x\nB |o..|{ C : y\nC {\n int id\n}")
        XCTAssertFalse(diagram.shapes.identifyingLines.isEmpty)
        XCTAssertFalse(diagram.shapes.nonIdentifyingLines.isEmpty)
        XCTAssertFalse(diagram.shapes.markFills.isEmpty)
        XCTAssertFalse(diagram.shapes.markOutlines.isEmpty)
        XCTAssertFalse(diagram.shapes.rowStripes.isEmpty)
        XCTAssertTrue(diagram.shapes.boxFills.boundingRect.contains(diagram.layout.entities[2].frame.insetBy(dx: 1, dy: 1)))
    }
}
