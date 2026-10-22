import XCTest
@testable import MermaidDiagrams

/// A state diagram painted into a bitmap at one pixel per point, its pixels read back.
final class StateDiagramRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func laidOut(_ source: String) throws -> StateDiagramLayout {
        try StateDiagramLayoutEngine.layout(StateDiagramReading.stateDiagram(source), typography: typography, limits: .standard)
    }

    private func drawn(_ layout: StateDiagramLayout, palette: DiagramPalette = .peleLight) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.draw(layout, palette: palette)
        return bitmap
    }

    private func frame(of kind: StateDiagramStateKind, in layout: StateDiagramLayout) throws -> CGRect {
        try XCTUnwrap(layout.states.first { state in state.kind == kind }?.frame)
    }

    private static let blueBackground = DiagramPalette(background: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), foreground: DiagramPalette.peleLight.foreground,
                                                       line: DiagramPalette.peleLight.line, surface: DiagramPalette.peleLight.surface,
                                                       border: DiagramPalette.peleLight.border)

    func testABoxIsFilledWithTheSurfaceOutlinedWithTheBorderAndHoldsItsName() throws {
        let layout = try laidOut("stateDiagram-v2\nStill --> Moving")
        let bitmap = try drawn(layout)
        let box = layout.states[0].frame
        XCTAssertEqual(bitmap.color(at: CGPoint(x: box.minX + 4, y: box.midY)), [0xF3, 0xF3, 0xF3])
        XCTAssertTrue(bitmap.color(at: CGPoint(x: box.minX + 0.5, y: box.midY)).allSatisfy { channel in channel < 0xF3 })
        XCTAssertTrue(bitmap.hasPixel(in: try XCTUnwrap(layout.states[0].name).frame, darkerThan: 0x80), "The name is drawn")
        XCTAssertEqual(bitmap.color(at: CGPoint(x: 1, y: 1)), [0xFF, 0xFF, 0xFF], "Nothing is drawn outside the shapes")
    }

    func testAStartIsASolidDotAndAnEndADotInARing() throws {
        let layout = try laidOut("stateDiagram-v2\n[*] --> A\nA --> [*]")
        let bitmap = try drawn(layout)
        let start = try frame(of: .start, in: layout)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: start.midX, y: start.midY)), [0x1F, 0x1F, 0x1F])
        let end = try frame(of: .end, in: layout)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: end.midX, y: end.midY)), [0x1F, 0x1F, 0x1F])
        XCTAssertTrue(bitmap.color(at: CGPoint(x: end.midX + 6.5, y: end.midY)).allSatisfy { channel in channel > 0xE0 }, "The background between")
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: end.maxX - 2, y: end.midY - 1, width: 2, height: 2), darkerThan: 0x80), "The ring")
    }

    func testAForkIsASolidBarAndAChoiceADiamondOfTheSurface() throws {
        let layout = try laidOut("stateDiagram-v2\nstate split <<fork>>\nstate pick <<choice>>\n[*] --> split\nsplit --> pick\nsplit --> B\npick --> C")
        let bitmap = try drawn(layout)
        let bar = try frame(of: .fork, in: layout)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: bar.midX, y: bar.midY)), [0x1F, 0x1F, 0x1F])
        let choice = try frame(of: .choice, in: layout)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: choice.midX, y: choice.midY)), [0xF3, 0xF3, 0xF3])
        XCTAssertEqual(bitmap.color(at: CGPoint(x: choice.minX + 2, y: choice.minY + 2)), [0xFF, 0xFF, 0xFF], "Outside the diamond")
    }

    func testATransitionIsALineWithAnArrowAndItsTextOnAPatch() throws {
        let layout = try laidOut("stateDiagram-v2\nA --> B : go")
        let bitmap = try drawn(layout, palette: Self.blueBackground)
        let tip = layout.transitions[0].arrow.tip
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: tip.x - 3, y: tip.y - 6, width: 6, height: 4), darkerThan: 0x80), "The arrow is filled")
        let text = try XCTUnwrap(layout.transitions[0].text)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: text.frame.minX - 2, y: text.frame.minY + 1)), [0, 0, 0xFF], "The patch is the background")
        XCTAssertTrue(bitmap.hasPixel(in: text.frame, darkerThan: 0x80), "The text is drawn")
    }

    func testANoteIsASheetOfTheBackgroundWithAFoldedCornerAndMutedText() throws {
        let layout = try laidOut("stateDiagram-v2\nA\nnote right of A : An aside")
        let note = layout.notes[0]
        let bitmap = try drawn(layout, palette: Self.blueBackground)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: note.frame.minX + 3, y: note.frame.midY)), [0, 0, 0xFF])
        XCTAssertEqual(bitmap.color(at: CGPoint(x: note.frame.maxX - 2, y: note.frame.minY + 2)), [0xFF, 0xFF, 0xFF], "The corner is folded away")
        let light = try drawn(layout)
        XCTAssertTrue(light.hasPixel(in: note.text.frame, darkerThan: 0xA0), "The text is drawn")
        XCTAssertFalse(light.hasPixel(in: note.text.frame, darkerThan: 0x50), "in a gray lighter than the text")
    }

    func testTheLineToANoteIsDashed() throws {
        let layout = try laidOut("stateDiagram-v2\nA\nnote right of A : An aside")
        let bitmap = try drawn(layout)
        let start = layout.notes[0].connector.start
        // A one-point line on a whole-point row covers two pixel rows by half: its dashes are about half as dark.
        let levels = (2..<40).map { offset in bitmap.color(at: CGPoint(x: start.x + CGFloat(offset), y: start.y))[0] }
        XCTAssertTrue(levels.contains { level in level < 0xE0 }, "Dashes")
        XCTAssertTrue(levels.contains { level in level > 0xFA }, "Gaps")
    }

    func testDrawingTheSameLayoutInOtherColorsChangesOnlyTheColors() throws {
        let layout = try laidOut("stateDiagram-v2\nA --> B")
        let dark = DiagramPalette(background: CGColor(gray: 0.1, alpha: 1), foreground: CGColor(gray: 0.9, alpha: 1), line: CGColor(gray: 0.9, alpha: 1),
                                  surface: CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1), border: CGColor(gray: 0.5, alpha: 1))
        let point = CGPoint(x: layout.states[0].frame.minX + 4, y: layout.states[0].frame.midY)
        XCTAssertEqual(try drawn(layout).color(at: point), [0xF3, 0xF3, 0xF3])
        XCTAssertEqual(try drawn(layout, palette: dark).color(at: point), [0x33, 0x33, 0x33])
    }

    func testANotesTextLiesBetweenTheBackgroundAndTheText() throws {
        let palette = DiagramPalette(background: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1), foreground: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                                     line: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1), surface: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                                     border: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
        let components = try XCTUnwrap(palette.noteText.components)
        XCTAssertEqual(components[0], 0.35, accuracy: 0.001)
        XCTAssertEqual(components[3], 1, accuracy: 0.001)
    }
}
