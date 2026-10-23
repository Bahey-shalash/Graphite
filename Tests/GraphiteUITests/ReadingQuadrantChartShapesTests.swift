import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingQuadrantChartShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAQuadrantChart: Error {}

    private func chart(_ source: String) throws -> ReadingQuadrantChart {
        guard case .quadrantChart(let chart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsAQuadrantChart()
        }
        return chart
    }

    func testQuadrantsAndPointGroupsKeepTheirPaths() throws {
        let chart = try chart("quadrantChart\n  A: [0.25, 0.25]\n  B: [0.75, 0.75] color: #ff3300, stroke-width: 2px")
        XCTAssertEqual(chart.shapes.quadrants.boundingRect.minX, chart.layout.quadrants[1].frame.minX, accuracy: 0.001)
        guard case .written(let color) = chart.shapes.pointGroups.first?.fill else { return XCTFail("B, written last, is painted first") }
        XCTAssertEqual([color.red, color.green, color.blue], [0xFF, 0x33, 0])
        XCTAssertEqual(chart.shapes.pointGroups.last?.fill, .firstSeries)
        XCTAssertEqual(chart.shapes.pointGroups.first?.stroke?.width, 2)
    }

    func testTextsAreQuadrantsThenPointsThenTheTitleAndTheAxesAreMuted() throws {
        let chart = try chart("quadrantChart\n  title Priorities\n  x-axis Low --> High\n  quadrant-1 Plan\n  A: [0.25, 0.25]")
        XCTAssertEqual(chart.shapes.textLines.map(\.text), ["Plan", "A", "Priorities"])
        XCTAssertEqual(chart.shapes.textLines.map(\.isBold), [false, false, true])
        XCTAssertEqual(chart.shapes.axisTextLines.map(\.text), ["Low", "High"])
        XCTAssertEqual(chart.shapes.axisTextLines.first?.font.size, 14, "The axes are seven eighths of the text size")
        XCTAssertEqual(chart.shapes.textLines[1].font.size, 12, "The points three quarters")
    }

    func testATurnedTextsLinesGoAcrossThePageInTheOrderTheyAreWritten() throws {
        let chart = try chart("quadrantChart\n  y-axis \"Low<br>impact\"")
        let label = chart.layout.axisLabels[0]
        XCTAssertTrue(label.isTurned)
        let lines = chart.shapes.turnedAxisTextLines
        XCTAssertEqual(lines.map(\.text), ["Low", "impact"])
        XCTAssertEqual(lines.map(\.center.y), [label.text.center.y, label.text.center.y])
        XCTAssertLessThan(lines[0].center.x, lines[1].center.x)
        XCTAssertEqual((lines[0].center.x + lines[1].center.x) / 2, label.text.center.x, accuracy: 0.001)
    }
}
