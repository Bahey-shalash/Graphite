import XCTest
@testable import MermaidDiagrams

final class XYChartDrawingPartsTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func parts(_ source: String) throws -> (XYChartLayout, XYChartDrawingParts) {
        let layout = try XYChartLayoutEngine.layout(try XYChartReading.chart(source), typography: typography)
        return (layout, XYChartDrawingParts(layout: layout))
    }

    func testBarsAndTheirSwatchesAreGroupedBySeriesColorAndTheColorsComeRoundAgain() throws {
        let series = (1...9).map { number in "bar \"Series \(number)\" [\(number)]" }.joined(separator: "\n")
        let (layout, parts) = try parts("xychart\nx-axis [a]\n" + series)
        XCTAssertEqual(parts.barFills.count, 8)
        let ninth = try XCTUnwrap(layout.bars.first { bar in bar.seriesIndex == 8 })
        XCTAssertTrue(parts.barFills[0].contains(CGPoint(x: ninth.frame.midX, y: ninth.frame.midY)), "The ninth series takes the first color")
        XCTAssertTrue(parts.barFills[0].contains(CGPoint(x: layout.legend[0].swatch.midX, y: layout.legend[0].swatch.midY)))
        XCTAssertTrue(parts.lines.isEmpty)
    }

    func testALinesStrokeHoldsItsRunsAndItsSwatchAndItsDotsAreCircles() throws {
        let (layout, parts) = try parts("xychart\nx-axis [a, b, c]\nline \"Trend\" [1, 2, 3]")
        let line = try XCTUnwrap(parts.lines.first)
        XCTAssertEqual(line.seriesIndex, 0)
        let swatch = layout.legend[0].swatch
        XCTAssertEqual(line.stroke.boundingBoxOfPath.maxX, swatch.maxX, accuracy: 0.001, "The swatch is part of the line's stroke")
        XCTAssertEqual(line.dots.boundingBoxOfPath.width, layout.lines[0].dots[2].x - layout.lines[0].dots[0].x + 6, accuracy: 0.001)
        XCTAssertTrue(parts.barFills.isEmpty)
    }

    func testTextIsGroupedByColorAndTheLeftTitleIsTurned() throws {
        let (layout, parts) = try parts("xychart\ntitle \"Sales\"\nx-axis \"Month\" [a, b]\ny-axis \"Revenue\" 0 --> 10\nline \"Trend\" [1 \"low\", 9]")
        XCTAssertEqual(parts.axisLabels, layout.axisLabels)
        XCTAssertEqual(parts.texts.map(\.lines), [["Month"], ["low"], ["Trend"]])
        XCTAssertEqual(parts.turnedText?.lines, ["Revenue"])
        XCTAssertEqual(parts.title?.lines, ["Sales"])
        XCTAssertFalse(parts.gridLines.isEmpty)
        XCTAssertFalse(parts.axisLines.isEmpty)
    }
}
