import XCTest
@testable import MermaidDiagrams

/// The entity relationship layout with uniform-width text: names 8 points a character (16-point text, 24-point
/// lines), rows and labels 7 (14-point text, 21-point lines), keys 6 (12-point text, 18-point lines).
final class EntityRelationshipLayoutEngineTests: XCTestCase {
    private let accuracy: CGFloat = 0.01

    private func layout(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> EntityRelationshipLayout {
        try EntityRelationshipUniformLayout.layout(source, limits: limits)
    }

    private func texts(_ row: EntityRelationshipLayoutRow, in column: EntityRelationshipColumn) -> [DiagramTextBlock] {
        row.texts.filter { cell in cell.column == column }.map(\.text)
    }

    func testABoxWithoutAttributesIsItsNamePaddedAndAtLeast96PointsWide() throws {
        let entities = try layout("erDiagram\nCUSTOMER\nA").entities
        XCTAssertEqual(entities[0].frame.size, CGSize(width: 64 + 36, height: 24 + 24))
        XCTAssertEqual(entities[1].frame.size, CGSize(width: 96, height: 48))
        XCTAssertEqual(entities[0].name.center.x, entities[0].frame.midX, accuracy: accuracy)
        XCTAssertEqual(entities[0].name.center.y, entities[0].frame.midY, accuracy: accuracy)
        XCTAssertTrue(entities[0].rows.isEmpty)
    }

    func testAttributesLineUpInColumnsUnderAHeader() throws {
        let entity = try XCTUnwrap(try layout("erDiagram\nCUSTOMER {\n string name PK \"The key\"\n int age\n}").entities.first)
        // Columns: "string" 42, "name" 28, "PK" 12, "The key" 49, with three 16-point gaps and 12 points each side.
        let columnsWidth: CGFloat = 42 + 28 + 12 + 49
        XCTAssertEqual(entity.frame.width, columnsWidth + 3 * 16 + 24, accuracy: accuracy)
        let headerHeight: CGFloat = 24 + 18
        XCTAssertEqual(entity.frame.height, headerHeight + 2 * (21 + 9), accuracy: accuracy)
        XCTAssertEqual(entity.name.center.y, entity.frame.minY + 21, accuracy: accuracy)
        XCTAssertEqual(entity.rows.map(\.frame.minY), [entity.frame.minY + 42, entity.frame.minY + 72])
        let first = entity.rows[0]
        let lefts = [EntityRelationshipColumn.type, .name, .keys, .comment].map { column in texts(first, in: column).first?.frame.minX ?? -1 }
        XCTAssertEqual(lefts.map { left in left - entity.frame.minX }, [12, 70, 114, 142])
        XCTAssertEqual(texts(first, in: .name).first?.center.y ?? 0, first.frame.minY + 4.5 + 10.5, accuracy: accuracy)
        let keys = try XCTUnwrap(texts(first, in: .keys).first)
        XCTAssertEqual(keys.fontSize, 12)
        XCTAssertEqual(keys.lines, ["PK"])
        XCTAssertEqual(keys.center.y + 12 * 0.35, first.frame.minY + 15 + 14 * 0.35, accuracy: accuracy, "Keys share the row's baseline")
        XCTAssertTrue(texts(entity.rows[1], in: .keys).isEmpty)
    }

    func testABoxWiderThanItsTableSharesTheSpareWidthBetweenItsColumns() throws {
        let entity = try XCTUnwrap(try layout("erDiagram\n\"A very long entity name here\" {\n int a\n}").entities.first)
        XCTAssertEqual(entity.frame.width, 28 * 8 + 36, accuracy: accuracy)
        let spare = (entity.frame.width - (21 + 7 + 16) - 24) / 2
        XCTAssertEqual((texts(entity.rows[0], in: .name).first?.frame.minX ?? 0) - entity.frame.minX, 12 + 21 + spare + 16, accuracy: accuracy)
    }

    func testAMultilineCommentWrapsAndGrowsItsRow() throws {
        let words = Array(repeating: "word", count: 12).joined(separator: " ")
        let entity = try XCTUnwrap(try layout("erDiagram\nA {\n string a \"\(words)\"\n}").entities.first)
        let comment = texts(entity.rows[0], in: .comment)
        XCTAssertEqual(comment.count, 2, "59 characters of 7 points wrap at 260")
        XCTAssertEqual(comment[1].center.y - comment[0].center.y, 21, accuracy: accuracy)
        XCTAssertEqual(comment[0].frame.minX, comment[1].frame.minX, accuracy: accuracy)
        XCTAssertEqual(entity.rows[0].frame.height, 2 * 21 + 9, accuracy: accuracy)
    }

    func testARelationshipRunsDownToTheSecondEntityPastItsLabel() throws {
        let laidOut = try layout("erDiagram\nA ||--o{ B : places")
        let (first, second) = (laidOut.entities[0].frame, laidOut.entities[1].frame)
        // The label "places" (42 + 12 by 21 + 4) takes a rank of its own, 32 points from each box.
        XCTAssertEqual(second.minY - first.maxY, 32 + 25 + 32, accuracy: accuracy)
        let relationship = try XCTUnwrap(laidOut.relationships.first)
        XCTAssertEqual(relationship.path.start, CGPoint(x: first.midX, y: first.maxY))
        XCTAssertEqual(relationship.path.segments, [.line(to: CGPoint(x: second.midX, y: second.minY))])
        XCTAssertEqual(relationship.firstEntityMark, EntityRelationshipCardinalityMark(cardinality: .exactlyOne, tip: CGPoint(x: first.midX, y: first.maxY),
                                                                                         direction: CGVector(dx: 0, dy: -1)))
        XCTAssertEqual(relationship.secondEntityMark, EntityRelationshipCardinalityMark(cardinality: .zeroOrMore, tip: CGPoint(x: second.midX, y: second.minY),
                                                                                          direction: CGVector(dx: 0, dy: 1)))
        XCTAssertEqual(relationship.label?.center.y ?? 0, (first.maxY + second.minY) / 2, accuracy: accuracy)
        XCTAssertEqual(relationship.identification, .identifying)
    }

    func testRelationshipsMeetingOneSideSpreadAndRunStraightBeforeTheyCurve() throws {
        let laidOut = try layout("erDiagram\nA ||..o{ B : x\nA ||--o{ C : y")
        let starts = laidOut.relationships.map(\.path.start)
        XCTAssertEqual(abs(starts[1].x - starts[0].x), 18, accuracy: accuracy)
        XCTAssertEqual(starts[0].y, laidOut.entities[0].frame.maxY, accuracy: accuracy)
        for relationship in laidOut.relationships {
            let start = relationship.path.start
            XCTAssertEqual(relationship.path.segments.first, .line(to: CGPoint(x: start.x, y: start.y + 18)))
            guard case .line(let end) = relationship.path.segments.last else { return XCTFail("Arrives straight") }
            XCTAssertEqual(end, relationship.secondEntityMark.tip)
            XCTAssertTrue(relationship.path.segments.contains { segment in
                if case .curve = segment { true } else { false }
            })
        }
        XCTAssertEqual(laidOut.relationships.map(\.identification), [.nonIdentifying, .identifying])
    }

    func testEachDirectionPlacesTheSecondEntityOnItsSide() throws {
        func secondFromFirst(_ direction: String) throws -> CGVector {
            let entities = try layout("erDiagram\ndirection \(direction)\nA ||--|| B : x").entities
            return CGVector(dx: entities[1].frame.midX - entities[0].frame.midX, dy: entities[1].frame.midY - entities[0].frame.midY)
        }
        XCTAssertGreaterThan(try secondFromFirst("TB").dy, 0)
        XCTAssertLessThan(try secondFromFirst("BT").dy, 0)
        XCTAssertGreaterThan(try secondFromFirst("LR").dx, 0)
        XCTAssertLessThan(try secondFromFirst("RL").dx, 0)
        XCTAssertEqual(try secondFromFirst("LR").dy, 0, accuracy: accuracy)
    }

    func testAnEntityRelatedToItselfLoopsOutOfItsRightSideWithItsLabelBeyond() throws {
        let laidOut = try layout("erDiagram\nNODE ||--o{ NODE : \"leads to\"")
        let box = laidOut.entities[0].frame
        let loop = try XCTUnwrap(laidOut.relationships.first)
        XCTAssertEqual(loop.firstEntityMark.tip.x, box.maxX, accuracy: accuracy)
        XCTAssertEqual(loop.secondEntityMark.tip.x, box.maxX, accuracy: accuracy)
        XCTAssertLessThan(loop.firstEntityMark.tip.y, loop.secondEntityMark.tip.y)
        XCTAssertEqual(loop.firstEntityMark.direction, CGVector(dx: -1, dy: 0))
        XCTAssertGreaterThan(try XCTUnwrap(loop.label).frame.minX, box.maxX + 18 + 21)
        XCTAssertLessThanOrEqual(try XCTUnwrap(loop.label).frame.maxX, laidOut.size.width)
        let twice = try layout("erDiagram\nNODE ||--o{ NODE : a\nNODE ||--|| NODE : b").entities[0].frame
        XCTAssertEqual(twice.height, 2 * 38 + 8, accuracy: accuracy, "Two loops' bands and the side's margins, taller than the name")
    }

    func testLoopsLeaveTheBottomWhenRanksRunAcross() throws {
        let laidOut = try layout("erDiagram\ndirection LR\nNODE {\n string id\n}\nNODE ||--o{ NODE : a\nNODE ||--|| NODE : b")
        let box = laidOut.entities[0].frame
        XCTAssertEqual(laidOut.relationships.map(\.firstEntityMark.tip.y), [box.maxY, box.maxY])
        XCTAssertEqual(laidOut.relationships[0].secondEntityMark.direction, CGVector(dx: 0, dy: -1))
        XCTAssertLessThan(laidOut.relationships[0].secondEntityMark.tip.x, laidOut.relationships[1].firstEntityMark.tip.x)
        XCTAssertGreaterThan(laidOut.size.height, box.maxY + 18 + 21)
    }

    func testBoxesDoNotOverlapAndTheDrawingKeepsItsPadding() throws {
        let laidOut = try layout("""
        erDiagram
        CUSTOMER ||--o{ ORDER : places
        ORDER ||--|{ LINE-ITEM : contains
        CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
        PRODUCT ||--o{ LINE-ITEM : "appears in"
        ORDER {
          int orderNumber PK
          string deliveryAddress
        }
        """)
        for (index, entity) in laidOut.entities.enumerated() {
            for other in laidOut.entities[(index + 1)...] { XCTAssertFalse(entity.frame.intersects(other.frame)) }
            XCTAssertGreaterThanOrEqual(entity.frame.minX, 8 - accuracy)
            XCTAssertGreaterThanOrEqual(entity.frame.minY, 8 - accuracy)
            XCTAssertLessThanOrEqual(entity.frame.maxX, laidOut.size.width - 8 + accuracy)
        }
    }

    func testTheTitleSitsAboveTheDiagram() throws {
        var diagram = try EntityRelationshipReading.diagram("erDiagram\nA")
        diagram.title = "Order example"
        let laidOut = try EntityRelationshipUniformLayout.layout(diagram)
        let title = try XCTUnwrap(laidOut.title)
        XCTAssertEqual(laidOut.entities[0].frame.minY, 8 + 24 + 12, accuracy: accuracy)
        XCTAssertEqual(title.center.x, laidOut.size.width / 2, accuracy: accuracy)
        XCTAssertEqual(laidOut.size.width, 13 * 8 + 16, accuracy: accuracy)
    }

    func testAnEmptyLabelTakesNoPlace() throws {
        let laidOut = try layout("erDiagram\nA ||--|| B : \"\"")
        XCTAssertNil(laidOut.relationships.first?.label)
        XCTAssertEqual(laidOut.entities[1].frame.minY - laidOut.entities[0].frame.maxY, 64, accuracy: accuracy)
    }

    func testSubgraphsAndTheLayoutLimitAreRefused() throws {
        XCTAssertThrowsError(try layout("erDiagram\nsubgraph group\nA\nend")) { error in
            XCTAssertEqual(error as? EntityRelationshipLayoutError, .subgraphsNotLaidOut)
        }
        var limits = MermaidDiagramLimits.standard
        limits.maximumLayoutPointCount = 2
        XCTAssertThrowsError(try layout("erDiagram\nA ||--|| B : x", limits: limits)) { error in
            XCTAssertEqual(error as? EntityRelationshipLayoutError, .tooManyLayoutPoints(limit: 2))
        }
    }
}
