import XCTest
@testable import MermaidDiagrams

/// Pixels read back from a bitmap a sequence diagram is drawn into, in Pele's light colors: a white page, #1f1f1f
/// text and lines, #f3f3f3 surfaces, #8a8a8a borders, and between them #6e6e6e muted text and a #e6e6e6 second surface.
final class SequenceRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func laidOut(_ body: String) throws -> SequenceLayout {
        try SequenceLayoutEngine.layout(SequenceReading.sequence("sequenceDiagram\n" + body), typography: typography)
    }

    private func drawn(_ layout: SequenceLayout, palette: DiagramPalette = .peleLight) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.draw(layout, palette: palette)
        return bitmap
    }

    /// The darkest channel of the darkest pixel in `rectangle`.
    private func darkestLevel(in bitmap: DiagramBitmap, _ rectangle: CGRect) -> Int {
        var darkest = 255
        for y in Int(rectangle.minY)..<Int(rectangle.maxY) {
            for x in Int(rectangle.minX)..<Int(rectangle.maxX) { darkest = min(darkest, bitmap.color(at: CGPoint(x: x, y: y)).max() ?? 255) }
        }
        return darkest
    }

    func testAParticipantIsABoxFilledWithTheSurfaceOutlinedWithTheBorderAboveAndBelowItsLifeline() throws {
        let layout = try laidOut("participant Alice\nAlice->>Bob: Hi")
        let bitmap = try drawn(layout)
        for participant in layout.participants {
            let frame = participant.frame
            XCTAssertEqual(bitmap.color(at: CGPoint(x: frame.minX + 4, y: frame.midY)), [0xF3, 0xF3, 0xF3])
            XCTAssertTrue(bitmap.color(at: CGPoint(x: frame.minX + 0.5, y: frame.midY)).allSatisfy { channel in channel < 0xF3 }, "The border")
            XCTAssertTrue(bitmap.hasPixel(in: participant.text.frame, darkerThan: 0x80), "The text")
        }
        XCTAssertEqual(bitmap.color(at: CGPoint(x: 1, y: 1)), [0xFF, 0xFF, 0xFF], "Nothing is drawn outside the shapes")
    }

    func testAnActorIsAStickFigureOverItsText() throws {
        let layout = try laidOut("actor Alice\nAlice->>Bob: Hi")
        let bitmap = try drawn(layout)
        let figure = layout.headers[0].frame
        XCTAssertEqual(bitmap.color(at: CGPoint(x: figure.midX, y: figure.minY + 7)), [0xF3, 0xF3, 0xF3], "The head is filled with the surface")
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: figure.midX - 1, y: figure.minY + 18, width: 2, height: 4), darkerThan: 0xD0), "The body")
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: figure.midX + 5, y: figure.minY + 26, width: 4, height: 7), darkerThan: 0xD0), "A leg")
    }

    func testALifelineRunsInTheBorderColorBetweenTheParticipants() throws {
        let layout = try laidOut("Alice->>Bob: Hi")
        let bitmap = try drawn(layout)
        let lifeline = layout.lifelines[0]
        let below = CGRect(x: lifeline.x - 1, y: lifeline.bottom - 10, width: 2, height: 8)
        XCTAssertTrue(bitmap.hasPixel(in: below, darkerThan: 0xF0))
        XCTAssertGreaterThan(darkestLevel(in: bitmap, below), 0x80, "Lighter than the text and lines")
    }

    func testAMessageIsALineInTheLineColorWithItsArrowAndItsTextAbove() throws {
        let layout = try laidOut("Alice->>Bob: Hi")
        let bitmap = try drawn(layout)
        let message = layout.messages[0]
        let lineY = message.path.start.y
        let middle = (layout.lifelines[0].x + layout.lifelines[1].x) / 2
        // A line one point wide on a whole coordinate covers two rows of pixels by half.
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: middle - 2, y: lineY - 1, width: 4, height: 2), darkerThan: 0xA0))
        let tip = try XCTUnwrap(message.heads.first?.tip)
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: tip.x - 5, y: tip.y - 2, width: 3, height: 4), darkerThan: 0x60), "The arrow is filled")
        XCTAssertTrue(bitmap.hasPixel(in: try XCTUnwrap(message.text?.frame), darkerThan: 0x80))
    }

    func testADottedMessageLeavesGapsInItsLine() throws {
        let layout = try laidOut("Alice-->Bob: Hi")
        let bitmap = try drawn(layout)
        let lineY = layout.messages[0].path.start.y
        let levels = stride(from: layout.lifelines[0].x + 6, to: layout.lifelines[1].x - 6, by: 1).map { x in
            bitmap.color(at: CGPoint(x: x, y: lineY - 0.5)).max() ?? 255
        }
        XCTAssertTrue(levels.contains { level in level < 0xA0 }, "Dashes")
        XCTAssertTrue(levels.contains { level in level > 0xF0 }, "Gaps")
    }

    func testANoteIsFilledWithTheSecondSurfaceAndAnActivationWithTheSurface() throws {
        let layout = try laidOut("Alice->>+Bob: Hi\nNote left of Alice: A note\nBob-->>-Alice: Bye")
        let bitmap = try drawn(layout)
        let note = layout.notes[0].frame
        XCTAssertEqual(bitmap.color(at: CGPoint(x: note.minX + 3, y: note.midY)), [0xE6, 0xE6, 0xE6])
        let activation = try XCTUnwrap(layout.activations.first)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: activation.midX, y: activation.midY)), [0xF3, 0xF3, 0xF3])
    }

    func testABlockHasATabFilledWithTheSurfaceAndItsWordsInTheMutedColor() throws {
        let layout = try laidOut("loop Every minute\nAlice->>Bob: Hi\nend")
        let bitmap = try drawn(layout)
        let block = try XCTUnwrap(layout.blocks.first)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: block.tab.minX + 3, y: block.tab.midY)), [0xF3, 0xF3, 0xF3])
        for words in [block.keyword.frame, try XCTUnwrap(block.title?.frame)] {
            let darkest = darkestLevel(in: bitmap, words)
            XCTAssertLessThan(darkest, 0x98, "The words are drawn")
            XCTAssertGreaterThanOrEqual(darkest, 0x6E - 2, "In the muted color, not the text's")
        }
    }

    func testAHighlightIsShadedInItsColorOrTheDefaultShade() throws {
        let layout = try laidOut("rect rgb(0, 0, 255)\nAlice->>Bob: Hi\nend\nrect\nAlice->>Bob: Hi\nend")
        let bitmap = try drawn(layout)
        let colored = layout.highlights.first { highlight in highlight.color != nil }
        let plain = layout.highlights.first { highlight in highlight.color == nil }
        let coloredFrame = try XCTUnwrap(colored?.frame)
        let plainFrame = try XCTUnwrap(plain?.frame)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: coloredFrame.minX + 3, y: coloredFrame.minY + 3)), [0, 0, 0xFF])
        let shade = bitmap.color(at: CGPoint(x: plainFrame.minX + 3, y: plainFrame.minY + 3))
        XCTAssertEqual(shade[0], (0xFF + 0xE6) / 2, accuracy: 2, "The second surface at half opacity")
    }

    func testANumberBadgeIsInTheLineColorAndItsNumberInTheBackground() throws {
        let layout = try laidOut("autonumber\nAlice->>Bob: Hi")
        let bitmap = try drawn(layout)
        let number = try XCTUnwrap(layout.messages[0].number)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: number.frame.midX, y: number.frame.minY + 1.5)), [0x1F, 0x1F, 0x1F])
        let numberFrame = number.text.frame.intersection(number.frame)
        var lightest = 0
        for y in Int(numberFrame.minY)..<Int(numberFrame.maxY) {
            for x in Int(numberFrame.minX)..<Int(numberFrame.maxX) { lightest = max(lightest, bitmap.color(at: CGPoint(x: x, y: y)).min() ?? 0) }
        }
        XCTAssertGreaterThan(lightest, 0xC0, "The number is drawn in the background color")
    }

    func testDrawingTheSameLayoutInOtherColorsChangesOnlyTheColors() throws {
        let layout = try laidOut("Alice->>Bob: Hi\nNote over Alice: n")
        let dark = DiagramPalette(background: CGColor(gray: 0, alpha: 1), foreground: CGColor(gray: 1, alpha: 1), line: CGColor(gray: 1, alpha: 1),
                                  surface: CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1), border: CGColor(gray: 0.5, alpha: 1))
        let point = CGPoint(x: layout.participants[0].frame.minX + 4, y: layout.participants[0].frame.midY)
        XCTAssertEqual(try drawn(layout).color(at: point), [0xF3, 0xF3, 0xF3])
        XCTAssertEqual(try drawn(layout, palette: dark).color(at: point), [0x33, 0x33, 0x33])
        let note = layout.notes[0].frame
        XCTAssertEqual(try drawn(layout, palette: dark).color(at: CGPoint(x: note.minX + 3, y: note.midY))[0], 0x1C, accuracy: 1,
                       "The second surface follows the page: 11 % of the way to the text")
    }
}
