import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingPieChartShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAPieChart: Error {}

    private func pieChart(_ source: String) throws -> ReadingPieChart {
        guard case .pieChart(let chart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAPieChart() }
        return chart
    }

    func testPercentagesInsideTheSlicesAreApartFromTheTextAroundThem() throws {
        let chart = try pieChart("pie title Pets\n \"Dogs\" : 386\n \"Cats\" : 85\n \"Rats\" : 15")
        XCTAssertEqual(chart.shapes.insidePercentageLines.map(\.text), ["79%", "17%"])
        XCTAssertEqual(chart.shapes.textLines.map(\.text), ["3%", "Dogs", "Cats", "Rats", "Pets"])
        XCTAssertEqual(chart.shapes.textLines.last?.isBold, true)
        XCTAssertEqual(chart.shapes.insidePercentageLines[0].center, chart.layout.slices[0].percentage.center)
    }

    func testEachSeriesColorHasOneFillAndTheColorsAreEnough() throws {
        let chart = try pieChart("pie\n" + (1...9).map { number in "\"\(number)\" : \(number)" }.joined(separator: "\n"))
        XCTAssertEqual(chart.shapes.seriesFills.count, 8)
        XCTAssertEqual(ReadingDiagramColors(background: .white, foreground: .black).series.count, chart.shapes.seriesFills.count)
    }

    func testTheEdgesOutlineThePieAndAnEmptyChartIsItsCircle() throws {
        let chart = try pieChart("pie\n \"a\" : 1\n \"b\" : 1")
        let pieFrame = CGRect(x: chart.layout.center.x - chart.layout.radius, y: chart.layout.center.y - chart.layout.radius,
                              width: 2 * chart.layout.radius, height: 2 * chart.layout.radius)
        XCTAssertEqual(chart.shapes.sliceEdges.boundingRect.width, pieFrame.width, accuracy: 0.001)
        XCTAssertTrue(chart.shapes.emptyPieOutline.isEmpty)
        let empty = try pieChart("pie\n \"zero\" : 0")
        XCTAssertTrue(empty.shapes.sliceEdges.isEmpty)
        XCTAssertFalse(empty.shapes.emptyPieOutline.isEmpty)
    }
}
