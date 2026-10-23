import XCTest
@testable import MermaidDiagrams

final class XYChartRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private let pele = DiagramPalette.peleLight
    /// A blue page, black text, a green grid, a red border and primary series colors, so that each part's color is
    /// told apart in every channel.
    private let primaries = DiagramPalette(background: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), foreground: CGColor(gray: 0, alpha: 1),
                                           line: CGColor(gray: 0, alpha: 1), surface: CGColor(gray: 0.95, alpha: 1),
                                           border: CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1),
                                           series: [CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1), CGColor(srgbRed: 0, green: 1, blue: 1, alpha: 1)],
                                           muted: CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1),
                                           alternateSurface: CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1))
    private let revenue = """
        xychart
            title "Sales Revenue"
            x-axis [jan, feb, mar, apr, may, jun]
            y-axis "Revenue (in $)" 4000 --> 11000
            bar [5000, 6000, 7500, 8200, 9500, 10500]
            line [5000, 6000, 7500, 8200, 9500, 10500]
        """

    private func drawn(_ source: String, palette: DiagramPalette) throws -> (XYChartLayout, DiagramBitmap) {
        let layout = try XYChartLayoutEngine.layout(try XYChartReading.chart(source), typography: typography)
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.paint { context in XYChartRenderer.draw(layout, in: context, palette: palette) }
        return (layout, bitmap)
    }

    private func hasPixel(in rectangle: CGRect, of bitmap: DiagramBitmap, where matches: ([Int]) -> Bool) -> Bool {
        for y in Int(rectangle.minY)..<Int(rectangle.maxY) {
            for x in Int(rectangle.minX)..<Int(rectangle.maxX) where matches(bitmap.color(at: CGPoint(x: x, y: y))) { return true }
        }
        return false
    }

    func testBarsAreFilledInPelesSeriesColorsInTheOrderTheSeriesAreWritten() throws {
        let (layout, bitmap) = try drawn("xychart\nx-axis [a, b]\ny-axis 0 --> 10\nbar [8, 8]\nbar [8, 8]", palette: pele)
        let first = try XCTUnwrap(layout.bars.first { bar in bar.seriesIndex == 0 })
        let second = try XCTUnwrap(layout.bars.first { bar in bar.seriesIndex == 1 })
        XCTAssertEqual(bitmap.color(at: CGPoint(x: first.frame.midX, y: first.frame.midY)), [0x4C, 0x78, 0xA8])
        XCTAssertEqual(bitmap.color(at: CGPoint(x: second.frame.midX, y: second.frame.midY)), [0xF5, 0x85, 0x18])
    }

    func testALineAndItsDotsAreDrawnOverTheBarsInItsOwnColor() throws {
        let (layout, bitmap) = try drawn(revenue, palette: primaries)
        let dot = try XCTUnwrap(layout.lines.first?.dots.last)
        XCTAssertEqual(bitmap.color(at: dot), [0, 0xFF, 0xFF], "The second series' color, over the first's bar")
        let bar = try XCTUnwrap(layout.bars.first)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: bar.frame.midX, y: bar.frame.maxY - 3)), [0xFF, 0xFF, 0])
    }

    func testTheGridAxesAndLabelsTakeTheirRolesColors() throws {
        let (layout, bitmap) = try drawn(revenue, palette: primaries)
        let grid = try XCTUnwrap(layout.gridLines.last)
        let gridBand = CGRect(x: grid.start.x + 4, y: grid.start.y - 1, width: 40, height: 3)
        XCTAssertTrue(hasPixel(in: gridBand, of: bitmap) { color in color[1] > color[0] + 0x40 && color[1] > color[2] + 0x40 }, "Green grid")
        let axisBand = CGRect(x: layout.plotFrame.minX - 1, y: layout.plotFrame.minY + 4, width: 3, height: 40)
        XCTAssertTrue(hasPixel(in: axisBand, of: bitmap) { color in color[0] > color[1] + 0x40 && color[0] > color[2] + 0x40 }, "Red axis")
        let label = try XCTUnwrap(layout.axisLabels.first)
        XCTAssertTrue(hasPixel(in: label.frame, of: bitmap) { color in color[0] > color[1] + 0x60 && color[2] > color[1] + 0x60 }, "Magenta labels")
        XCTAssertTrue(bitmap.hasPixel(in: try XCTUnwrap(layout.title).frame, darkerThan: 0x40), "Black title")
    }

    func testTheLeftTitleReadsFromTheBottomUp() throws {
        let (layout, bitmap) = try drawn(revenue, palette: pele)
        let title = try XCTUnwrap(layout.leftAxisTitle)
        let halfHeight = title.size.height / 2
        let upperPart = CGRect(x: title.center.x - halfHeight, y: title.center.y - title.size.width / 2 + 4, width: 2 * halfHeight,
                               height: title.size.width / 2 - halfHeight - 6)
        XCTAssertTrue(bitmap.hasPixel(in: upperPart, darkerThan: 0x80), "Turned, the title runs down the page's side")
        let besideIt = CGRect(x: title.center.x + halfHeight + 2, y: title.center.y - halfHeight, width: title.size.width / 2 - halfHeight - 4,
                              height: 2 * halfHeight)
        XCTAssertFalse(bitmap.hasPixel(in: besideIt, darkerThan: 0xC0), "Not across")
    }

    func testTheSameLayoutDrawsInAnyPalette() throws {
        let (layout, light) = try drawn("xychart\nx-axis [a]\nbar [1]", palette: pele)
        let (_, colored) = try drawn("xychart\nx-axis [a]\nbar [1]", palette: primaries)
        let middle = CGPoint(x: layout.bars[0].frame.midX, y: layout.bars[0].frame.midY)
        XCTAssertEqual(light.color(at: middle), [0x4C, 0x78, 0xA8])
        XCTAssertEqual(colored.color(at: middle), [0xFF, 0xFF, 0])
    }
}
