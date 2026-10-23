import XCTest
@testable import MermaidDiagrams

/// The renderer's pixels, read back from a bitmap at one pixel per point, in Pele's light colors.
final class EntityRelationshipRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func laidOut(_ source: String) throws -> EntityRelationshipLayout {
        try EntityRelationshipLayoutEngine.layout(EntityRelationshipReading.diagram(source), typography: typography, limits: .standard)
    }

    private func drawn(_ layout: EntityRelationshipLayout, palette: DiagramPalette = .peleLight) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.paint { context in EntityRelationshipRenderer.draw(layout, in: context, palette: palette) }
        return bitmap
    }

    /// The darkest channel of any pixel of `rectangle`.
    private func darkestChannel(in rectangle: CGRect, of bitmap: DiagramBitmap) -> Int {
        var darkest = 255
        for y in Int(rectangle.minY)..<Int(rectangle.maxY.rounded(.up)) {
            for x in Int(rectangle.minX)..<Int(rectangle.maxX.rounded(.up)) {
                darkest = min(darkest, bitmap.color(at: CGPoint(x: x, y: y)).min() ?? 255)
            }
        }
        return darkest
    }

    func testABoxIsFilledItsFirstRowStripedAndItsHeaderDivided() throws {
        let layout = try laidOut("erDiagram\nCUSTOMER {\n string name\n int age\n}")
        let bitmap = try drawn(layout)
        let entity = layout.entities[0]
        let left = entity.frame.minX + 4
        XCTAssertEqual(bitmap.color(at: CGPoint(x: left, y: entity.frame.minY + 6)), [0xF3, 0xF3, 0xF3], "The header is the surface")
        XCTAssertEqual(bitmap.color(at: CGPoint(x: left, y: entity.rows[0].frame.midY)), [0xFF, 0xFF, 0xFF], "The first row is striped")
        XCTAssertEqual(bitmap.color(at: CGPoint(x: left, y: entity.rows[1].frame.midY)), [0xF3, 0xF3, 0xF3], "The second is not")
        let divider = CGRect(x: entity.frame.minX + 6, y: entity.rows[0].frame.minY - 1, width: 4, height: 2)
        XCTAssertLessThan(darkestChannel(in: divider, of: bitmap), 0xD0, "The header's divider")
        XCTAssertLessThan(darkestChannel(in: CGRect(x: entity.frame.minX, y: entity.frame.midY, width: 1, height: 1), of: bitmap), 0xD0, "The outline")
        XCTAssertEqual(bitmap.color(at: CGPoint(x: 1, y: 1)), [0xFF, 0xFF, 0xFF], "Nothing is drawn outside the box")
    }

    func testTypesKeysAndCommentsAreMutedAndNamesAreNot() throws {
        let layout = try laidOut("erDiagram\nCUSTOMER {\n string name PK \"The key\"\n}")
        let bitmap = try drawn(layout)
        let texts = layout.entities[0].rows[0].texts
        func darkest(_ column: EntityRelationshipColumn) throws -> Int {
            darkestChannel(in: try XCTUnwrap(texts.first { cell in cell.column == column }).text.frame, of: bitmap)
        }
        XCTAssertLessThan(try darkest(.name), 0x40, "The attribute's name in the text color")
        XCTAssertLessThan(darkestChannel(in: layout.entities[0].name.frame, of: bitmap), 0x40, "The entity's name in the text color")
        for column in [EntityRelationshipColumn.type, .keys, .comment] {
            let darkestChannel = try darkest(column)
            XCTAssertGreaterThan(darkestChannel, 0x60, "\(column) is muted")
            XCTAssertLessThan(darkestChannel, 0xA0, "\(column) is drawn")
        }
    }

    func testAnIdentifyingLineIsSolidAndANonIdentifyingOneDashed() throws {
        func rowsCrossed(_ source: String) throws -> (dark: Int, all: Int) {
            let layout = try laidOut(source)
            let bitmap = try drawn(layout)
            let x = layout.relationships[0].path.start.x
            let rows = Int(layout.entities[0].frame.maxY) + 20..<Int(layout.entities[1].frame.minY) - 20
            let dark = rows.filter { y in darkestChannel(in: CGRect(x: x - 1, y: CGFloat(y), width: 2, height: 1), of: bitmap) < 0xC0 }
            return (dark.count, rows.count)
        }
        let solid = try rowsCrossed("erDiagram\nA ||--|| B : \"\"")
        XCTAssertEqual(solid.dark, solid.all)
        let dashed = try rowsCrossed("erDiagram\nA ||..|| B : \"\"")
        XCTAssertGreaterThan(dashed.dark, 0)
        XCTAssertLessThan(dashed.dark, dashed.all)
    }

    func testARingHidesTheLineUnderItAndABarCrossesIt() throws {
        let layout = try laidOut("erDiagram\nA |o--|| B : \"\"")
        let bitmap = try drawn(layout)
        let tip = layout.relationships[0].firstEntityMark.tip
        XCTAssertGreaterThan(darkestChannel(in: CGRect(x: tip.x - 1, y: tip.y + 12.5, width: 2, height: 2), of: bitmap), 0xE0, "The ring's middle")
        XCTAssertLessThan(darkestChannel(in: CGRect(x: tip.x + 2.5, y: tip.y + 12.5, width: 2, height: 2), of: bitmap), 0xC0, "The ring")
        XCTAssertLessThan(darkestChannel(in: CGRect(x: tip.x + 3, y: tip.y + 5, width: 2, height: 2), of: bitmap), 0xC0, "The bar")
        XCTAssertLessThan(darkestChannel(in: CGRect(x: tip.x - 1, y: tip.y + 30, width: 2, height: 1), of: bitmap), 0xC0, "The line")
    }

    func testEveryCardinalityIsDrawnBesideTheLineWithinAMarksLength() throws {
        for (symbol, cardinality) in [("||", EntityRelationshipCardinality.exactlyOne), ("|o", .zeroOrOne), ("}|", .oneOrMore), ("}o", .zeroOrMore),
                                      ("u", .parent)] {
            let layout = try laidOut("erDiagram\nA \(symbol)--|| B : \"\"")
            let bitmap = try drawn(layout)
            let mark = layout.relationships[0].firstEntityMark
            XCTAssertEqual(mark.cardinality, cardinality)
            let beside = CGRect(x: mark.tip.x + 2, y: mark.tip.y + 1, width: 3, height: EntityRelationshipCardinalityMark.length - 1)
            XCTAssertLessThan(darkestChannel(in: beside, of: bitmap), 0xC0, "\(cardinality)")
            let beyond = CGRect(x: mark.tip.x + 8, y: mark.tip.y + 1, width: 4, height: EntityRelationshipCardinalityMark.length)
            XCTAssertGreaterThan(darkestChannel(in: beyond, of: bitmap), 0xF0, "\(cardinality) stays near the line")
        }
    }

    func testALabelSitsOnAPatchOfTheBackgroundThatHidesTheLine() throws {
        let layout = try laidOut("erDiagram\nA ||--o{ B : places")
        let light = DiagramPalette.peleLight
        let blueBackground = DiagramPalette(background: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), foreground: light.foreground, line: light.line,
                                            surface: light.surface, border: light.border)
        let label = try XCTUnwrap(layout.relationships[0].label)
        let bitmap = try drawn(layout, palette: blueBackground)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: label.frame.minX - 2, y: label.frame.midY)), [0, 0, 0xFF])
        XCTAssertLessThan(darkestChannel(in: label.frame, of: bitmap), 0x40, "The label's text")
    }

    func testDrawingTheSameLayoutInOtherColorsChangesOnlyTheColors() throws {
        let layout = try laidOut("erDiagram\nCUSTOMER {\n string name\n}")
        let dark = DiagramPalette(background: CGColor(gray: 0.1, alpha: 1), foreground: CGColor(gray: 0.9, alpha: 1), line: CGColor(gray: 0.9, alpha: 1),
                                  surface: CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1), border: CGColor(gray: 0.5, alpha: 1))
        let header = CGPoint(x: layout.entities[0].frame.minX + 4, y: layout.entities[0].frame.minY + 6)
        XCTAssertEqual(try drawn(layout).color(at: header), [0xF3, 0xF3, 0xF3])
        XCTAssertEqual(try drawn(layout, palette: dark).color(at: header), [0x33, 0x33, 0x33])
    }
}
