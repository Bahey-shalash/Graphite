import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingXYChartShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAnXYChart: Error {}

    private func chart(_ source: String) throws -> ReadingXYChart {
        guard case .xyChart(let chart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAnXYChart() }
        return chart
    }

    func testBarsArePaintedPerSeriesColorAndLinesOneByOne() throws {
        let chart = try chart("xychart\n  x-axis [a, b]\n  bar [1, 2]\n  line [2, 1]\n  bar [2, 2]")
        XCTAssertEqual(chart.shapes.barFills.count, 3, "Colors up to the last bar series' place")
        XCTAssertTrue(chart.shapes.barFills[1].isEmpty, "The line's place has no bars")
        XCTAssertEqual(chart.shapes.lines.map(\.seriesIndex), [1])
        XCTAssertFalse(chart.shapes.lines[0].dots.isEmpty)
        XCTAssertLessThanOrEqual(chart.shapes.barFills.count, ReadingDiagramColors(background: .white, foreground: .black).series.count)
    }

    func testTheTextIsGroupedByColorWithTheTitleLastAndBold() throws {
        let chart = try chart("xychart\n  title \"Sales\"\n  x-axis \"Month\" [jan, feb]\n  y-axis \"Revenue\" 0 --> 10\n  bar \"Units\" [1, 2]")
        XCTAssertEqual(chart.shapes.axisLabelLines.map(\.text), chart.layout.axisLabels.flatMap(\.lines))
        XCTAssertEqual(chart.shapes.textLines.map(\.text), ["Month", "Units", "Sales"])
        XCTAssertEqual(chart.shapes.textLines.last?.isBold, true)
    }

    func testTheLeftTitlesLinesAreTurnedAboutItsCenter() throws {
        let chart = try chart("xychart\n  y-axis \"Revenue<br>in dollars\" 0 --> 10\n  bar [1, 2]")
        let title = try XCTUnwrap(chart.layout.leftAxisTitle)
        let turned = chart.shapes.turnedTextLines
        XCTAssertEqual(turned.map(\.text), ["Revenue", "in dollars"])
        XCTAssertEqual(turned[0].center.y, title.center.y, accuracy: 0.001)
        XCTAssertEqual(turned[1].center.x - turned[0].center.x, title.lineHeight, accuracy: 0.001, "The second line is right of the first")
        XCTAssertEqual((turned[0].center.x + turned[1].center.x) / 2, title.center.x, accuracy: 0.001)
    }
}
