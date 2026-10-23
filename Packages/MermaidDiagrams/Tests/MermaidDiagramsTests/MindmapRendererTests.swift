import XCTest
@testable import MermaidDiagrams

/// Pixels read back from a bitmap a mindmap is drawn into, in Pele's colors on a white page.
final class MindmapRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func laidOut(_ source: String) throws -> MindmapLayout {
        MindmapLayoutEngine.layout(try MindmapReading.mindmap(source), typography: typography)
    }

    private func drawn(_ layout: MindmapLayout, palette: DiagramPalette = .peleLight) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.paint { context in MindmapRenderer.draw(layout, in: context, palette: palette) }
        return bitmap
    }

    /// White blended with `color` at Pele's tint, 0 to 255 per channel.
    private func tint(_ red: Int, _ green: Int, _ blue: Int) -> [Int] {
        [red, green, blue].map { channel in Int((Double(channel) * 0.22 + 255 * 0.78).rounded()) }
    }

    private func assertColor(_ color: [Int], near expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(color.count, 3, file: file, line: line)
        for (channel, value) in zip(color, expected) { XCTAssertEqual(Double(channel), Double(value), accuracy: 2, "\(color)", file: file, line: line) }
    }

    func testEachBranchsNodesAreTintedAndOutlinedInItsSeriesColor() throws {
        let layout = try laidOut("mindmap\n  root\n    a[Alpha]\n    b[Beta]")
        let bitmap = try drawn(layout)
        let right = layout.nodes[1].frame
        let left = layout.nodes[2].frame
        assertColor(bitmap.color(at: CGPoint(x: right.minX + 4, y: right.midY)), near: tint(0x4C, 0x78, 0xA8))
        assertColor(bitmap.color(at: CGPoint(x: left.minX + 4, y: left.midY)), near: tint(0xF5, 0x85, 0x18))
        let outline = (-1...1).map { offset in bitmap.color(at: CGPoint(x: right.minX + CGFloat(offset), y: right.midY)) }
        XCTAssertTrue(outline.contains { color in color[2] > color[0] + 50 }, "The outline is in the branch's blue: \(outline)")
        XCTAssertTrue(bitmap.hasPixel(in: layout.nodes[1].text.frame, darkerThan: 0x80), "The text is drawn")
    }

    func testTheRootIsFilledWithTheSurfaceAndOutlinedWithTheBorder() throws {
        let layout = try laidOut("mindmap\n  root\n    child")
        let bitmap = try drawn(layout)
        let root = layout.nodes[0].frame
        XCTAssertEqual(bitmap.color(at: CGPoint(x: root.minX + 14, y: root.midY)), [0xF3, 0xF3, 0xF3])
        XCTAssertTrue(bitmap.color(at: CGPoint(x: root.midX, y: root.minY + 0.5)).allSatisfy { channel in channel < 0xD0 })
        XCTAssertEqual(bitmap.color(at: CGPoint(x: 1, y: 1)), [0xFF, 0xFF, 0xFF], "Nothing is drawn outside the shapes")
    }

    func testALinkIsDrawnInItsBranchsColor() throws {
        let layout = try laidOut("mindmap\n  root\n    a[Alpha]\n    b[Beta]")
        let bitmap = try drawn(layout)
        let root = layout.nodes[0].frame
        let middleRight = CGPoint(x: (root.maxX + layout.nodes[1].frame.minX) / 2, y: root.midY)
        let middleLeft = CGPoint(x: (layout.nodes[2].frame.maxX + root.minX) / 2, y: root.midY)
        let blue = (-1...1).map { offset in bitmap.color(at: CGPoint(x: middleRight.x, y: middleRight.y + CGFloat(offset))) }
        let orange = (-1...1).map { offset in bitmap.color(at: CGPoint(x: middleLeft.x, y: middleLeft.y + CGFloat(offset))) }
        XCTAssertTrue(blue.contains { color in color[2] > color[0] + 40 }, "\(blue)")
        XCTAssertTrue(orange.contains { color in color[0] > color[2] + 60 }, "\(orange)")
    }

    func testATextNodeHasNoOutlineAndAPillHasOne() throws {
        let layout = try laidOut("mindmap\n  root\n    middle\n      leaf")
        let bitmap = try drawn(layout)
        let pill = layout.nodes[1].frame
        let leaf = layout.nodes[2].frame
        assertColor(bitmap.color(at: CGPoint(x: pill.midX, y: pill.minY + 2)), near: tint(0x4C, 0x78, 0xA8))
        XCTAssertEqual(bitmap.color(at: CGPoint(x: leaf.minX + 2, y: leaf.minY + 1)), [0xFF, 0xFF, 0xFF])
        XCTAssertTrue(bitmap.hasPixel(in: leaf, darkerThan: 0x80), "The leaf's text is drawn")
    }

    func testOtherSeriesColorsChangeOnlyTheColors() throws {
        let layout = try laidOut("mindmap\n  root\n    a[Alpha]")
        var palette = DiagramPalette.peleLight
        palette.series = [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)]
        let point = CGPoint(x: layout.nodes[1].frame.minX + 4, y: layout.nodes[1].frame.midY)
        assertColor(try drawn(layout).color(at: point), near: tint(0x4C, 0x78, 0xA8))
        assertColor(try drawn(layout, palette: palette).color(at: point), near: tint(0xFF, 0, 0))
    }

    func testEveryOutlineIsDrawnAroundItsText() throws {
        let layout = try laidOut("mindmap\n  root\n    a[Rect]\n    b(Rounded)\n    c((Circle))\n    d)Cloud(\n    e))Bang((\n    f{{Hexagon}}\n    g\n      h")
        let bitmap = try drawn(layout)
        for node in layout.nodes.dropFirst() where node.outline != .text {
            let left = CGPoint(x: node.text.frame.minX - 4, y: node.frame.midY)
            XCTAssertNotEqual(bitmap.color(at: left), [0xFF, 0xFF, 0xFF], "\(node.outline) is filled beside its text")
        }
    }
}
