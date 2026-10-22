import XCTest
@testable import MermaidDiagrams

final class EntityRelationshipDrawingPartsTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func parts(_ source: String) throws -> (EntityRelationshipLayout, EntityRelationshipDrawingParts) {
        let layout = try EntityRelationshipUniformLayout.layout(source)
        return (layout, EntityRelationshipDrawingParts(layout: layout))
    }

    /// The mark of `cardinality` at the origin, on a line that comes up from below into a box above.
    private func markPaths(_ cardinality: EntityRelationshipCardinality) -> (fills: CGPath, outlines: CGPath) {
        let fills = CGMutablePath()
        let outlines = CGMutablePath()
        let mark = EntityRelationshipCardinalityMark(cardinality: cardinality, tip: .zero, direction: CGVector(dx: 0, dy: -1))
        EntityRelationshipCardinalityDrawing.addMark(mark, fills: fills, outlines: outlines)
        return (fills, outlines)
    }

    private func assertBounds(_ path: CGPath, _ expected: CGRect, _ message: String, line: UInt = #line) {
        let bounds = path.boundingBoxOfPath
        for (actual, wanted) in [(bounds.minX, expected.minX), (bounds.minY, expected.minY), (bounds.maxX, expected.maxX), (bounds.maxY, expected.maxY)] {
            XCTAssertEqual(actual, wanted, accuracy: accuracy, message, line: line)
        }
    }

    func testEachCardinalityDrawsItsCrowsFootMarkWithinAMarksLengthOfTheBox() {
        assertBounds(markPaths(.exactlyOne).outlines, CGRect(x: -5, y: 6, width: 10, height: 4), "Two bars")
        assertBounds(markPaths(.zeroOrOne).outlines, CGRect(x: -5, y: 6, width: 10, height: 11), "A bar and a ring")
        assertBounds(markPaths(.zeroOrOne).fills, CGRect(x: -3.5, y: 10, width: 7, height: 7), "The ring hides the line")
        assertBounds(markPaths(.oneOrMore).outlines, CGRect(x: -6, y: 0, width: 12, height: 13.5), "A foot and a bar")
        assertBounds(markPaths(.zeroOrMore).outlines, CGRect(x: -6, y: 0, width: 12, height: 17.5), "A foot and a ring")
        assertBounds(markPaths(.zeroOrMore).fills, CGRect(x: -3.5, y: 10.5, width: 7, height: 7), "The ring hides the line")
        assertBounds(markPaths(.parent).fills, CGRect(x: -4, y: 0, width: 8, height: 12), "A hollow diamond")
        XCTAssertTrue(markPaths(.exactlyOne).fills.isEmpty)
        XCTAssertTrue(markPaths(.oneOrMore).fills.isEmpty)
        for cardinality in EntityRelationshipCardinality.allCases {
            XCTAssertLessThanOrEqual(markPaths(cardinality).outlines.boundingBoxOfPath.maxY, EntityRelationshipCardinalityMark.length)
        }
    }

    func testEachIdentificationGoesToItsOwnPathAndEveryMarkIsDrawn() throws {
        let (layout, drawn) = try parts("erDiagram\nA }o--o{ B : x\nB |o..|{ C : y")
        XCTAssertEqual(drawn.identifyingLines.boundingBoxOfPath.minY, layout.entities[0].frame.maxY, accuracy: accuracy)
        XCTAssertEqual(drawn.nonIdentifyingLines.boundingBoxOfPath.minY, layout.entities[1].frame.maxY, accuracy: accuracy)
        XCTAssertFalse(drawn.markFills.isEmpty)
        XCTAssertEqual(drawn.markOutlines.boundingBoxOfPath.minY, layout.entities[0].frame.maxY, accuracy: accuracy)
        XCTAssertEqual(drawn.markOutlines.boundingBoxOfPath.maxY, layout.entities[2].frame.minY, accuracy: accuracy)
    }

    func testTheFirstRowAndEverySecondOneAreStriped() throws {
        let (three, threeRows) = try parts("erDiagram\nA {\n int a\n int b\n int c\n}")
        let rows = three.entities[0].rows
        assertBounds(threeRows.rowStripes, CGRect(x: rows[0].frame.minX, y: rows[0].frame.minY, width: rows[0].frame.width,
                                                  height: rows[2].frame.maxY - rows[0].frame.minY), "Rows one and three")
        let (two, twoRows) = try parts("erDiagram\nA {\n int a\n int b\n}")
        assertBounds(twoRows.rowStripes, two.entities[0].rows[0].frame, "Row one only")
        XCTAssertTrue(try parts("erDiagram\nA").1.rowStripes.isEmpty)
    }

    func testABoxIsOutlinedAndItsHeaderDivided() throws {
        let (layout, drawn) = try parts("erDiagram\nA {\n int a\n}")
        let frame = layout.entities[0].frame
        assertBounds(drawn.boxFills, frame, "The box")
        let stroked = drawn.boxOutlines.copy(strokingWithWidth: 1, lineCap: .butt, lineJoin: .miter, miterLimit: 10)
        XCTAssertTrue(stroked.contains(CGPoint(x: frame.midX, y: layout.entities[0].rows[0].frame.minY)))
        XCTAssertFalse(stroked.contains(CGPoint(x: frame.midX, y: frame.minY + 10)))
    }

    func testNamesAreTextAndTypesKeysAndCommentsAreMuted() throws {
        let (_, drawn) = try parts("erDiagram\nCUSTOMER {\n string name PK \"The key\"\n int age\n}")
        XCTAssertEqual(drawn.entityTexts.flatMap(\.lines), ["CUSTOMER", "name", "age"])
        XCTAssertEqual(drawn.attributeDetails.flatMap(\.lines), ["string", "PK", "The key", "int"])
    }

    func testALabelGetsAPatchSlightlyWiderThanItself() throws {
        let (layout, drawn) = try parts("erDiagram\nA ||--o{ B : places")
        let label = try XCTUnwrap(layout.relationships[0].label)
        XCTAssertEqual(drawn.labels, [label])
        XCTAssertEqual(drawn.labelPatches.boundingBoxOfPath.width, label.frame.width + 8, accuracy: accuracy)
    }
}
