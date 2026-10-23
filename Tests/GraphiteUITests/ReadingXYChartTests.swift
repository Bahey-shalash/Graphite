import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingXYChartTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsAnXYChart: Error {}

    private func chart(_ source: String) throws -> ReadingXYChart {
        guard case .xyChart(let chart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAnXYChart() }
        return chart
    }

    func testAnXYChartIsLaidOutInTheNotesTextSize() throws {
        let chart = try chart("xychart\n  title \"Sales\"\n  x-axis [jan, feb]\n  line [1 \"low\", 2]")
        XCTAssertEqual(chart.layout.font.size, 17)
        XCTAssertEqual(chart.layout.title?.fontSize, 17)
        XCTAssertEqual(chart.layout.axisLabels.first?.fontSize, 15, "Seven eighths of the text size, rounded")
        XCTAssertEqual(chart.layout.pointLabels.first?.fontSize, 13, "Three quarters of the text size, rounded")
    }

    func testAScreenReaderHearsTheTitleAndEachSeriesWithItsValues() throws {
        let chart = try chart("xychart\n  title \"Sales\"\n  x-axis [jan, feb, mar]\n  bar \"Revenue\" [5000, 6000.5]\n  line [1, 2, 3]")
        XCTAssertEqual(chart.title, "Sales")
        XCTAssertNil(chart.description)
        XCTAssertEqual(chart.seriesSummaries, ["Revenue: jan 5000, feb 6000.5", "Line: jan 1, feb 2, mar 3"])
        XCTAssertEqual(try self.chart("xychart\n  bar [3, 4]").seriesSummaries, ["Bars: 3, 4"])
        let described = try self.chart("xychart\n  title \"Shown\"\n  accTitle: Spoken\n  accDescr: What it shows\n  bar [1]")
        XCTAssertEqual(described.title, "Spoken")
        XCTAssertEqual(described.description, "What it shows")
    }

    func testAnXYChartThatCannotBeReadOrLaidOutKeepsItsSourceAndWhy() throws {
        let source = "xychart\n  line [1, , 2]"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .expectedSeriesValues)))
        guard case .unreadable(_, let empty) = try XCTUnwrap(ReadingDiagram(source: "xychart\n  x-axis [a]", typography: typography)) else {
            return XCTFail("A chart without series is shown as unreadable")
        }
        XCTAssertEqual(empty, .xyChartLayout(.noSeries))
    }

    func testTheXYChartsProblemsAreExplainedApartFromTheOthers() {
        let problems: [MermaidSyntaxProblem] = [.expectedChartText, .expectedAxisRange, .expectedCategories, .expectedSeriesValues, .unexpectedText("x")]
        var failures = problems.map { problem in ReadingDiagramFailure.reading(.invalidSyntax(line: 1, problem: problem)) }
        failures += [.reading(.tooManyChartValues(limit: 5_000)), .reading(.tooManyNodes(limit: 5_000)), .xyChartLayout(.noSeries)]
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
    }
}
