import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingPieChartTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsAPieChart: Error {}

    private func pieChart(_ source: String) throws -> ReadingPieChart {
        guard case .pieChart(let chart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAPieChart() }
        return chart
    }

    func testAPieChartIsLaidOutInTheNotesTextSize() throws {
        let chart = try pieChart("pie title Pets\n \"Dogs\" : 386\n \"Cats\" : 85\n \"Rats\" : 15")
        XCTAssertEqual(chart.layout.font.size, 17)
        XCTAssertEqual(chart.layout.title?.fontSize, 17)
        XCTAssertEqual(chart.layout.legend.first?.text.fontSize, 15, "Seven eighths of the text size, rounded")
        XCTAssertEqual(chart.layout.slices.count, 3)
    }

    func testAScreenReaderHearsTheTitleAndEachSliceWithItsShare() throws {
        let chart = try pieChart("pie showData title Pets\n \"Dogs\" : 386\n \"Cats\" : 85\n \"Tiny\" : 1")
        XCTAssertEqual(chart.title, "Pets")
        XCTAssertNil(chart.description)
        XCTAssertEqual(chart.sliceSummaries, ["Dogs [386] 82%", "Cats [85] 18%", "Tiny [1]"], "A slice under one percent is not drawn")
        let described = try pieChart("pie title Shown\naccTitle: Spoken\naccDescr: What it shows\n\"a\" : 1")
        XCTAssertEqual(described.title, "Spoken")
        XCTAssertEqual(described.description, "What it shows")
    }

    func testAPieChartThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "pie\n\"dogs\" : -1"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .negativeSliceValue(label: "dogs"))))
    }

    func testThePieChartsProblemsAreExplainedApartFromTheOthers() {
        let problems: [MermaidSyntaxProblem] = [.expectedSliceValue, .negativeSliceValue(label: "dogs"), .unexpectedText("x"), .unclosedQuotation]
        let failures = problems.map { problem in ReadingDiagramFailure.reading(.invalidSyntax(line: 1, problem: problem)) }
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
    }
}
