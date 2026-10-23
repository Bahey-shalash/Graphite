import XCTest
@testable import MermaidDiagrams

/// Pixels read back from a bitmap a Git graph is drawn into, in Pele's colors on a white page.
final class GitGraphRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private let blue = [0x4C, 0x78, 0xA8]
    private let orange = [0xF5, 0x85, 0x18]
    private let white = [0xFF, 0xFF, 0xFF]

    private func laidOut(_ source: String) throws -> GitGraphLayout {
        try GitGraphLayoutEngine.layout(GitGraphReading.gitGraph(source), typography: typography)
    }

    private func drawn(_ layout: GitGraphLayout, palette: DiagramPalette = .peleLight) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.paint { context in GitGraphRenderer.draw(layout, in: context, palette: palette) }
        return bitmap
    }

    private func assertColor(_ color: [Int], near expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(color.count, 3, file: file, line: line)
        for (channel, value) in zip(color, expected) { XCTAssertEqual(Double(channel), Double(value), accuracy: 3, "\(color)", file: file, line: line) }
    }

    private func offset(_ point: CGPoint, _ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
        CGPoint(x: point.x + dx, y: point.y + dy)
    }

    func testCommitsAreDotsInTheirLanesSeriesColor() throws {
        let layout = try laidOut("gitGraph\n commit\n branch b\n commit")
        let bitmap = try drawn(layout)
        assertColor(bitmap.color(at: layout.commits[0].center), near: blue)
        assertColor(bitmap.color(at: layout.commits[1].center), near: orange)
        assertColor(bitmap.color(at: offset(layout.commits[0].center, 5, 0)), near: blue)
    }

    func testAHighlightIsASquareAndAMergeARing() throws {
        let layout = try laidOut("gitGraph\n commit type:HIGHLIGHT\n branch b\n commit\n checkout main\n merge b")
        let bitmap = try drawn(layout)
        assertColor(bitmap.color(at: offset(layout.commits[0].center, 6.5, 6.5)), near: blue)
        let ring = layout.commits[2].center
        assertColor(bitmap.color(at: ring), near: blue)
        assertColor(bitmap.color(at: offset(ring, 4, 0)), near: white)
        assertColor(bitmap.color(at: offset(ring, 0, -6)), near: blue)
    }

    func testAReverseCommitIsCrossedInTheBackgroundColor() throws {
        let layout = try laidOut("gitGraph\n commit type:REVERSE")
        let bitmap = try drawn(layout)
        let center = layout.commits[0].center
        XCTAssertTrue(bitmap.color(at: center).allSatisfy { channel in channel > 0xD0 }, "\(bitmap.color(at: center))")
        assertColor(bitmap.color(at: offset(center, 5, 0)), near: blue)
    }

    func testABranchsNameIsInItsColorAndItsLaneIsDashed() throws {
        let layout = try laidOut("gitGraph\n commit\n commit")
        let bitmap = try drawn(layout)
        let box = try XCTUnwrap(layout.lanes[0].nameFrame)
        assertColor(bitmap.color(at: CGPoint(x: box.minX + 3, y: box.midY)), near: blue)
        let lane = layout.lanes[0]
        let between = (Int(layout.commits[0].center.x) + 8)..<(Int(layout.commits[1].center.x) - 8)
        let colors = between.map { x in bitmap.color(at: CGPoint(x: CGFloat(x), y: lane.lineStart.y)) }
        XCTAssertTrue(colors.contains { color in color[2] > color[0] + 0x30 }, "The connector runs over the lane in its color")
        let lead = (Int(box.maxX) + 1)..<(Int(layout.commits[0].center.x) - 8)
        let leadColors = lead.map { x in bitmap.color(at: CGPoint(x: CGFloat(x), y: lane.lineStart.y)) }
        XCTAssertTrue(leadColors.contains { color in color == white }, "The lane is dashed before the first commit")
        XCTAssertTrue(leadColors.contains { color in color[2] > color[0] + 0x20 }, "The lane is dashed before the first commit")
    }

    func testATagIsABoxInTheSurfaceColorOutlinedInTheBorderColor() throws {
        let layout = try laidOut("gitGraph\n commit tag:\"release\"")
        let bitmap = try drawn(layout)
        let tag = try XCTUnwrap(layout.commits[0].tags.first)
        assertColor(bitmap.color(at: CGPoint(x: tag.frame.maxX - 3, y: tag.frame.midY)), near: [0xF3, 0xF3, 0xF3])
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: tag.frame.maxX - 1, y: tag.frame.midY, width: 2, height: 1), darkerThan: 0xD0), "The tag is outlined")
        XCTAssertTrue(bitmap.hasPixel(in: tag.text.frame, darkerThan: 0x80), "The tag's text is drawn")
    }

    func testAnIdIsDrawnTurnedOnItsPatch() throws {
        let layout = try laidOut("gitGraph\n commit id:\"abcdefgh\"")
        let bitmap = try drawn(layout)
        let label = try XCTUnwrap(layout.commits[0].label)
        let center = label.text.center
        let around = CGRect(x: center.x - 12, y: center.y - 12, width: 24, height: 24)
        XCTAssertTrue(bitmap.hasPixel(in: around, darkerThan: 0xA0), "The id's text is drawn about its center")
        let reach = label.text.size.width / 2 * 0.8
        let alongText = CGPoint(x: center.x + reach * cos(label.angle), y: center.y + reach * sin(label.angle))
        let acrossText = CGPoint(x: center.x + reach, y: center.y)
        let nearAlongText = CGRect(x: alongText.x - 3, y: alongText.y - 3, width: 6, height: 6)
        XCTAssertTrue(bitmap.hasPixel(in: nearAlongText, darkerThan: 0xA0), "The text runs along its turn")
        assertColor(bitmap.color(at: acrossText), near: white)
    }

    func testOtherSeriesColorsChangeOnlyTheColors() throws {
        let layout = try laidOut("gitGraph\n commit")
        var palette = DiagramPalette.peleLight
        palette.series = [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)]
        assertColor(try drawn(layout, palette: palette).color(at: layout.commits[0].center), near: [0xFF, 0, 0])
    }
}
