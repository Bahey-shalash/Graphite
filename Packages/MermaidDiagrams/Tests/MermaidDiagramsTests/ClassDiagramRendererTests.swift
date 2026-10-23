import XCTest
@testable import MermaidDiagrams

/// A class diagram painted into a bitmap, its pixels read back.
final class ClassDiagramRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private let red = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)

    private func laidOut(_ source: String) throws -> ClassDiagramLayout {
        try ClassDiagramLayoutEngine.layout(ClassDiagramReading.classDiagram(source), typography: typography, limits: .standard)
    }

    private func drawn(_ layout: ClassDiagramLayout, palette: ClassDiagramPalette = .peleLight) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.draw(layout, palette: palette)
        return bitmap
    }

    /// How many pixels of the row at `y` between `minimumX` and `maximumX` are darker than `level` in every channel.
    private func darkPixelCount(in bitmap: DiagramBitmap, y: CGFloat, from minimumX: CGFloat, to maximumX: CGFloat, darkerThan level: Int) -> Int {
        (Int(minimumX)..<Int(maximumX)).filter { x in bitmap.color(at: CGPoint(x: CGFloat(x), y: y)).allSatisfy { channel in channel < level } }.count
    }

    func testABoxIsFilledWithTheSurfaceOutlinedAndDividedWithTheBorder() throws {
        let layout = try laidOut("classDiagram\nclass Duck {\n  +String beakColor\n  +swim()\n}")
        let bitmap = try drawn(layout)
        let duck = layout.classes[0]
        XCTAssertEqual(bitmap.color(at: CGPoint(x: duck.frame.minX + 4, y: duck.frame.minY + 4)), [0xF3, 0xF3, 0xF3])
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: duck.frame.minX, y: duck.frame.midY, width: 1, height: 1), darkerThan: 0xF0), "The outline")
        for y in duck.dividerYs {
            XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: duck.frame.minX + 3, y: y - 1, width: 3, height: 2), darkerThan: 0xE0), "A divider at \(y)")
        }
        XCTAssertEqual(bitmap.color(at: CGPoint(x: 1, y: 1)), [0xFF, 0xFF, 0xFF], "Nothing is drawn outside")
    }

    func testTheNameAndEachMemberAreDrawnInTheirRows() throws {
        let layout = try laidOut("classDiagram\nclass Duck {\n  +String beakColor\n  +swim()\n}")
        let bitmap = try drawn(layout)
        let duck = layout.classes[0]
        XCTAssertTrue(bitmap.hasPixel(in: duck.name.frame, darkerThan: 0x80))
        for member in duck.members { XCTAssertTrue(bitmap.hasPixel(in: member.text.frame, darkerThan: 0x80), member.text.lines.joined()) }
    }

    func testATriangleAndAnAggregationsDiamondAreHollowAndACompositionsIsFilled() throws {
        for (relation, isFilled) in [("<|--", false), ("o--", false), ("*--", true)] {
            let layout = try laidOut("classDiagram\nA \(relation) B")
            let bitmap = try drawn(layout)
            let mark = try XCTUnwrap(layout.relations.first?.sourceMark)
            let inside = CGPoint(x: mark.tip.x - mark.direction.dx * 8, y: mark.tip.y - mark.direction.dy * 8)
            let isDark = bitmap.color(at: inside).allSatisfy { channel in channel < 0x80 }
            XCTAssertEqual(isDark, isFilled, relation)
            XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: inside.x - 7, y: inside.y - 1, width: 14, height: 2), darkerThan: 0x80), "\(relation) is outlined")
        }
    }

    func testAnArrowIsFilledAndARingIsHollow() throws {
        let arrow = try laidOut("classDiagram\nA --> B")
        let arrowMark = try XCTUnwrap(arrow.relations.first?.targetMark)
        XCTAssertTrue(try drawn(arrow).hasPixel(in: CGRect(x: arrowMark.tip.x - 2, y: arrowMark.tip.y - 5, width: 4, height: 3), darkerThan: 0x80))
        let ring = try laidOut("classDiagram\nA ()--() B")
        let ringMark = try XCTUnwrap(ring.relations.first?.targetMark)
        let center = CGPoint(x: ringMark.tip.x, y: ringMark.tip.y - 5)
        XCTAssertEqual(try drawn(ring).color(at: center), [0xFF, 0xFF, 0xFF])
    }

    func testADashedRelationHasGapsAndASolidOneHasNone() throws {
        for (relation, hasGaps) in [("..", true), ("--", false)] {
            let layout = try laidOut("classDiagram\nA \(relation) B")
            let bitmap = try drawn(layout)
            let x = layout.classes[0].frame.midX
            let top = layout.classes[0].frame.maxY + 3
            let bottom = layout.classes[1].frame.minY - 3
            let lightCount = stride(from: top, to: bottom, by: 1).filter { y in
                !bitmap.hasPixel(in: CGRect(x: x - 1, y: y, width: 2, height: 1), darkerThan: 0xC0)
            }.count
            XCTAssertEqual(lightCount > 0, hasGaps, relation)
        }
    }

    func testANoteIsFilledWithTheNoteColorAndItsTextDrawn() throws {
        let layout = try laidOut("classDiagram\nnote \"Hello\"")
        let bitmap = try drawn(layout)
        let note = try XCTUnwrap(layout.notes.first)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: note.frame.minX + 3, y: note.frame.maxY - 3)), [0xE6, 0xE6, 0xE6])
        XCTAssertTrue(bitmap.hasPixel(in: note.text.frame, darkerThan: 0x80))
    }

    func testAnnotationsAndCardinalitiesAreDrawnInTheMutedColor() throws {
        let layout = try laidOut("classDiagram\nclass Shape <<interface>>\nShape \"1\" --> \"many\" Other")
        var palette = ClassDiagramPalette.peleLight
        palette.muted = red
        let bitmap = try drawn(layout, palette: palette)
        func hasRed(in frame: CGRect) -> Bool {
            (Int(frame.minY)..<Int(frame.maxY)).contains { y in
                (Int(frame.minX)..<Int(frame.maxX)).contains { x in
                    let color = bitmap.color(at: CGPoint(x: x, y: y))
                    return color[0] > 0xA0 && color[1] < 0x60 && color[2] < 0x60
                }
            }
        }
        XCTAssertTrue(hasRed(in: layout.classes[0].annotations[0].frame))
        XCTAssertTrue(hasRed(in: try XCTUnwrap(layout.relations.first?.targetCardinality).frame))
        XCTAssertFalse(hasRed(in: layout.classes[0].name.frame))
    }

    func testAStaticMemberIsUnderlined() throws {
        let layout = try laidOut("classDiagram\nclass A {\n  +count()$ int\n  +name\n}")
        let bitmap = try drawn(layout)
        let members = layout.classes[0].members
        func underlineCount(_ member: ClassDiagramLayoutMember) -> Int {
            let text = member.text
            let y = text.center.y + text.fontSize * (DiagramTextDrawing.baselineShiftRatio + ClassDiagramDrawingParts.underlineDropRatio)
            return darkPixelCount(in: bitmap, y: y, from: text.frame.minX + 1, to: text.frame.maxX - 1, darkerThan: 0xA0)
        }
        XCTAssertEqual(members.map(\.classifier), [.plain, .static], "Attributes come before methods")
        XCTAssertGreaterThan(underlineCount(members[1]), Int(members[1].text.size.width * 0.8))
        XCTAssertLessThan(underlineCount(members[0]), Int(members[0].text.size.width * 0.2))
    }

    func testDrawingTheSameLayoutInOtherColorsChangesOnlyTheColors() throws {
        let layout = try laidOut("classDiagram\nclass A\nnote for A \"About A\"")
        var palette = ClassDiagramPalette.peleLight
        palette.diagram.surface = red
        let point = CGPoint(x: layout.classes[0].frame.minX + 4, y: layout.classes[0].frame.minY + 4)
        XCTAssertEqual(try drawn(layout).color(at: point), [0xF3, 0xF3, 0xF3])
        XCTAssertEqual(try drawn(layout, palette: palette).color(at: point), [0xFF, 0, 0])
    }
}
