import XCTest
@testable import MermaidDiagrams

/// A quadrant chart drawn into a bitmap at one pixel per point, its pixels read back: the quadrants, the points in their
/// colors and order, an outline, the turned axis text.
final class QuadrantChartRendererTests: XCTestCase {
    private static let palette = DiagramPalette(background: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
                                                foreground: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                                                line: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1),
                                                surface: CGColor(srgbRed: 0.95, green: 0.95, blue: 0.95, alpha: 1),
                                                border: CGColor(srgbRed: 0.54, green: 0.54, blue: 0.54, alpha: 1))

    private func drawn(_ source: String, palette: DiagramPalette = palette) throws -> (QuadrantChartLayout, DiagramBitmap) {
        let layout = try QuadrantChartReading.uniformLayout(source)
        let bitmap = try XCTUnwrap(DiagramBitmap(size: layout.size))
        bitmap.paint { context in QuadrantChartRenderer.draw(layout, in: context, palette: palette) }
        return (layout, bitmap)
    }

    private func assertColor(_ color: [Int], is expected: [Int], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(color.count, 3, file: file, line: line)
        for (channel, value) in zip(color, expected) { XCTAssertEqual(Double(channel), Double(value), accuracy: 3, file: file, line: line) }
    }

    func testQuadrantsAreFilledInTheSurfaceAndOutlinedInTheBorderColor() throws {
        let (layout, bitmap) = try drawn("quadrantChart\n quadrant-1 Plan")
        let frame = layout.quadrants[2].frame
        assertColor(bitmap.color(at: CGPoint(x: frame.minX + 6, y: frame.midY)), is: [242, 242, 242])
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: frame.minX - 1, y: frame.midY - 2, width: 2, height: 4), darkerThan: 200))
        assertColor(bitmap.color(at: CGPoint(x: frame.maxX + 2, y: frame.midY)), is: [255, 255, 255]) // The gap between quadrants.
    }

    func testPointsAreInTheFirstSeriesColorUnlessTheChartWritesOne() throws {
        let (layout, bitmap) = try drawn("quadrantChart\n A: [0.25, 0.25]\n B: [0.75, 0.75] color: #00ff33")
        assertColor(bitmap.color(at: layout.points[0].center), is: [76, 120, 168])
        assertColor(bitmap.color(at: layout.points[1].center), is: [0, 255, 51])
    }

    func testTheFirstPointIsDrawnOnTop() throws {
        let (layout, bitmap) = try drawn("quadrantChart\n First: [0.5, 0.5] color: #ff0000\n Second: [0.5, 0.5] color: #0000ff")
        assertColor(bitmap.color(at: layout.points[0].center), is: [255, 0, 0])
    }

    func testAnOutlineIsDrawnOnlyWithAWidth() throws {
        let source = "quadrantChart\n A: [0.25, 0.5] radius: 10, stroke-color: #000000, stroke-width: 4px\n B: [0.75, 0.5] radius: 10, stroke-color: #000000"
        let (layout, bitmap) = try drawn(source)
        let outlined = layout.points[0].center
        assertColor(bitmap.color(at: CGPoint(x: outlined.x + 10, y: outlined.y)), is: [0, 0, 0])
        let plain = layout.points[1].center
        XCTAssertFalse(bitmap.hasPixel(in: CGRect(x: plain.x + 9, y: plain.y - 1, width: 3, height: 2), darkerThan: 40), "A stroke color without a width")
    }

    func testTheYAxisTextIsTurnedAQuarter() throws {
        let (layout, bitmap) = try drawn("quadrantChart\n y-axis Engagement")
        let center = layout.axisLabels[0].text.center
        XCTAssertTrue(layout.axisLabels[0].isTurned)
        // Flat, the text would reach 10 points above and below its middle at most; turned, its ends are 24 to 34 away.
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: center.x - 8, y: center.y - 34, width: 16, height: 10), darkerThan: 200))
        XCTAssertTrue(bitmap.hasPixel(in: CGRect(x: center.x - 8, y: center.y + 24, width: 16, height: 10), darkerThan: 200))
    }

    func testTheTitleAndTheTextsAreDrawn() throws {
        let (layout, bitmap) = try drawn(QuadrantChartReading.reachAndEngagement)
        XCTAssertTrue(bitmap.hasPixel(in: try XCTUnwrap(layout.title).frame, darkerThan: 100))
        XCTAssertTrue(bitmap.hasPixel(in: try XCTUnwrap(layout.quadrants[0].text).frame, darkerThan: 100))
        XCTAssertTrue(bitmap.hasPixel(in: layout.points[0].text.frame, darkerThan: 100))
    }

    func testTheSameLayoutPaintsInAnotherPalette() throws {
        var dark = Self.palette
        dark.surface = CGColor(srgbRed: 0.2, green: 0.2, blue: 0.2, alpha: 1)
        dark.series = [CGColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)]
        let source = "quadrantChart\n A: [0.25, 0.25]"
        let (layout, light) = try drawn(source)
        let (_, darkBitmap) = try drawn(source, palette: dark)
        let inside = CGPoint(x: layout.quadrants[0].frame.minX + 6, y: layout.quadrants[0].frame.midY)
        assertColor(darkBitmap.color(at: inside), is: [51, 51, 51])
        assertColor(light.color(at: inside), is: [242, 242, 242])
        assertColor(darkBitmap.color(at: layout.points[0].center), is: [255, 255, 0])
    }
}
