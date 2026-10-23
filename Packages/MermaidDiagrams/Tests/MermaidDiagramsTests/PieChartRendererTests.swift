import XCTest
@testable import MermaidDiagrams

final class PieChartRendererTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private let pets = "pie title Pets adopted by volunteers\n    \"Dogs\" : 386\n    \"Cats\" : 85\n    \"Rats\" : 15\n"
    /// A blue page, black text and primary series colors, so that each part's color is told apart in every channel.
    private let primaries = DiagramPalette(background: CGColor(srgbRed: 0, green: 0, blue: 1, alpha: 1), foreground: CGColor(gray: 0, alpha: 1),
                                           line: CGColor(gray: 0, alpha: 1), surface: CGColor(gray: 0.95, alpha: 1), border: CGColor(gray: 0, alpha: 1),
                                           series: [CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1), CGColor(srgbRed: 0, green: 1, blue: 0, alpha: 1),
                                                    CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)])

    private func laidOut(_ source: String) throws -> PieChartLayout {
        PieChartLayoutEngine.layout(try PieChartReading.pieChart(source), typography: typography)
    }

    private func drawn(_ layout: PieChartLayout, palette: DiagramPalette = DiagramPalette(background: CGColor(gray: 1, alpha: 1),
                                                                                           foreground: CGColor(gray: 0.12, alpha: 1),
                                                                                           line: CGColor(gray: 0.12, alpha: 1),
                                                                                           surface: CGColor(gray: 0.95, alpha: 1),
                                                                                           border: CGColor(gray: 0.54, alpha: 1))) throws -> DiagramBitmap {
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        PieChartRenderer.draw(layout, in: bitmap.context, palette: palette)
        return bitmap
    }

    private func point(_ layout: PieChartLayout, angle: CGFloat, distance: CGFloat) -> CGPoint {
        PieChartSlicePlacement.point(at: angle, distance: distance, from: layout.center)
    }

    func testSlicesAreFilledInPelesSeriesColorsClockwiseFromTheTop() throws {
        let layout = try laidOut(pets)
        let bitmap = try drawn(layout)
        XCTAssertEqual(bitmap.color(at: point(layout, angle: .pi / 2, distance: 60)), [0x4C, 0x78, 0xA8], "Dogs, from the top round the right")
        XCTAssertEqual(bitmap.color(at: point(layout, angle: 3 * .pi / 2, distance: 60)), [0x4C, 0x78, 0xA8], "Dogs, to the left")
        XCTAssertEqual(bitmap.color(at: point(layout, angle: 5.5, distance: 50)), [0xF5, 0x85, 0x18], "Cats")
        XCTAssertEqual(bitmap.color(at: point(layout, angle: 6.19, distance: 100)), [0x54, 0xA2, 0x4B], "Rats, just before the top")
        XCTAssertEqual(bitmap.color(at: point(layout, angle: .pi / 4, distance: 125)), [0xFF, 0xFF, 0xFF], "Nothing beyond the rim")
    }

    func testNeighbouringSlicesAreSeparatedByALineOfTheBackground() throws {
        let layout = try laidOut(pets)
        let bitmap = try drawn(layout, palette: primaries)
        XCTAssertEqual(bitmap.color(at: CGPoint(x: layout.center.x + 30, y: layout.center.y - 60)), [0xFF, 0, 0])
        XCTAssertGreaterThan(bitmap.color(at: CGPoint(x: layout.center.x - 0.5, y: layout.center.y - 60))[2], 0x40, "The edge at the top")
    }

    func testPercentagesInsideAreInTheBackgroundAndTheLegendInTheText() throws {
        let layout = try laidOut(pets)
        let bitmap = try drawn(layout, palette: primaries)
        let inside = try XCTUnwrap(layout.slices.first { slice in slice.percentagePlacement == .insideSlice }?.percentage)
        XCTAssertTrue(hasPixel(in: inside.frame, of: bitmap) { color in color[2] > 0x80 && color[0] < 0x80 }, "Blue text on red")
        let outside = try XCTUnwrap(layout.slices.first { slice in slice.percentagePlacement == .outsideRim }?.percentage)
        XCTAssertTrue(bitmap.hasPixel(in: outside.frame, darkerThan: 0x80))
        XCTAssertTrue(bitmap.hasPixel(in: layout.legend[0].text.frame, darkerThan: 0x80))
        XCTAssertTrue(bitmap.hasPixel(in: try XCTUnwrap(layout.title).frame, darkerThan: 0x80))
    }

    func testEachSwatchTakesItsSlicesColorAndTheColorsComeRoundAgain() throws {
        let slices = (1...9).map { number in "\"Slice \(number)\" : 1" }.joined(separator: "\n")
        let layout = try laidOut("pie\n" + slices)
        let bitmap = try drawn(layout, palette: primaries)
        let swatchColors = layout.legend.map { entry in bitmap.color(at: CGPoint(x: entry.swatch.midX, y: entry.swatch.midY)) }
        XCTAssertEqual(swatchColors[0], [0xFF, 0, 0])
        XCTAssertEqual(swatchColors[1], [0, 0xFF, 0])
        XCTAssertEqual(swatchColors[2], [0xFF, 0xFF, 0])
        XCTAssertEqual(swatchColors[3], [0xFF, 0, 0], "Three colors given: the fourth slice takes the first")
        XCTAssertEqual(swatchColors[8], swatchColors[0], "The ninth slice takes the first of Pele's eight places")
    }

    func testAChartWithoutValuesDrawsTheCircleInTheBorderColor() throws {
        let layout = try laidOut("pie\n \"Zero\" : 0")
        let bitmap = try drawn(layout)
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: layout.center.x + layout.radius - 1, y: layout.center.y - 2, width: 2, height: 4), darkerThan: 0xD0))
        XCTAssertEqual(bitmap.color(at: layout.center), [0xFF, 0xFF, 0xFF], "Not filled")
    }

    private func hasPixel(in rectangle: CGRect, of bitmap: DiagramBitmap, where matches: ([Int]) -> Bool) -> Bool {
        for y in Int(rectangle.minY)..<Int(rectangle.maxY) {
            for x in Int(rectangle.minX)..<Int(rectangle.maxX) where matches(bitmap.color(at: CGPoint(x: x, y: y))) { return true }
        }
        return false
    }
}
