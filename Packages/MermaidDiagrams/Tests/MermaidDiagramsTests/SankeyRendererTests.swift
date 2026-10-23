import XCTest
@testable import MermaidDiagrams

final class SankeyRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    /// Black text, magenta muted text and primary series colors, so that each part's color is told apart.
    private let primaries = DiagramPalette(background: CGColor(gray: 1, alpha: 1), foreground: CGColor(gray: 0, alpha: 1), line: CGColor(gray: 0, alpha: 1),
                                           surface: CGColor(gray: 0.95, alpha: 1), border: CGColor(gray: 0.5, alpha: 1),
                                           series: [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1)],
                                           muted: CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1))

    private func drawn(_ source: String, palette: DiagramPalette = .peleLight) throws -> (SankeyLayout, DiagramBitmap) {
        let layout = try SankeyLayoutEngine.layout(try SankeyReading.diagram(source), typography: typography)
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.paint { context in SankeyRenderer.draw(layout, in: context, palette: palette) }
        return (layout, bitmap)
    }

    private func hasPixel(in rectangle: CGRect, of bitmap: DiagramBitmap, where matches: ([Int]) -> Bool) -> Bool {
        for y in Int(rectangle.minY)..<Int(rectangle.maxY) {
            for x in Int(rectangle.minX)..<Int(rectangle.maxX) where matches(bitmap.color(at: CGPoint(x: x, y: y))) { return true }
        }
        return false
    }

    func testBarsAreFilledInPelesSeriesColorsByTheOrderNodesAreNamed() throws {
        let (layout, bitmap) = try drawn("sankey\na,b,10\na,c,5")
        let colors = layout.nodes.map { node in bitmap.color(at: CGPoint(x: node.frame.midX, y: node.frame.midY)) }
        XCTAssertEqual(colors, [[0x4C, 0x78, 0xA8], [0xF5, 0x85, 0x18], [0x54, 0xA2, 0x4B]])
    }

    func testABandFadesFromItsSourcesColorToItsTargetsAtFortyPercent() throws {
        let (layout, bitmap) = try drawn("sankey\na,b,10", palette: primaries)
        let band = layout.links[0]
        let nearStart = bitmap.color(at: CGPoint(x: band.startX + 2, y: band.sourceY))
        let nearEnd = bitmap.color(at: CGPoint(x: band.endX - 2, y: band.targetY))
        XCTAssertEqual(Double(nearStart[0]), 255, accuracy: 2, "Red at 40 % over white")
        XCTAssertEqual(Double(nearStart[1]), 0.6 * 255, accuracy: 4)
        XCTAssertEqual(Double(nearStart[2]), 0.6 * 255, accuracy: 6, "A trace of the target's blue already")
        XCTAssertEqual(Double(nearEnd[2]), 255, accuracy: 2, "Blue at the end")
        XCTAssertEqual(Double(nearEnd[0]), 0.6 * 255, accuracy: 6)
    }

    func testNamesAreInTheTextColorAndValuesInTheMutedColor() throws {
        let (layout, bitmap) = try drawn("sankey\nSource,Target,10", palette: primaries)
        let label = layout.labels[0]
        XCTAssertTrue(bitmap.hasPixel(in: label.name.frame, darkerThan: 0x40))
        XCTAssertTrue(hasPixel(in: label.value.frame, of: bitmap) { color in color[0] > color[1] + 0x60 && color[2] > color[1] + 0x60 })
        XCTAssertFalse(hasPixel(in: label.name.frame, of: bitmap) { color in color[0] > color[1] + 0x60 && color[2] > color[1] + 0x60 })
    }

    func testTheSameLayoutDrawsInAnyPalette() throws {
        let (layout, light) = try drawn("sankey\na,b,1")
        let (_, colored) = try drawn("sankey\na,b,1", palette: primaries)
        let middle = CGPoint(x: layout.nodes[1].frame.midX, y: layout.nodes[1].frame.midY)
        XCTAssertEqual(light.color(at: middle), [0xF5, 0x85, 0x18])
        XCTAssertEqual(colored.color(at: middle), [0, 0, 0xFF])
    }
}
