import XCTest
import MermaidDiagrams
@testable import GraphiteUI

/// The reading view's Gantt charts. Charts whose dates are all before the day the tests run lay out the same whatever
/// that day; the moment and time zone are given wherever they matter.
final class ReadingGanttChartTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsAGanttChart: Error {}
    private let chart = """
    gantt
        title Launch plan
        dateFormat YYYY-MM-DD
        section Build
        Design : a1, 2014-01-01, 10d
        Implement : after a1, 20d
    """

    private func ganttChart(_ source: String) throws -> ReadingGanttChart {
        guard case .ganttChart(let chart) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAGanttChart() }
        return chart
    }

    func testAGanttChartIsLaidOutInTheNotesTextSize() throws {
        let gantt = try ganttChart(chart)
        XCTAssertEqual(gantt.layout.font.size, 17)
        XCTAssertEqual(gantt.layout.plot?.tasks.count, 2)
        XCTAssertEqual(gantt.layout.plot?.tasks.first?.label.fontSize, 14, "Thirteen sixteenths of the text size, rounded")
    }

    func testAScreenReaderHearsTheTitleAndTheTasks() throws {
        let gantt = try ganttChart(chart)
        XCTAssertEqual(gantt.title, "Launch plan")
        XCTAssertEqual(gantt.taskNames, ["Design", "Implement"])
        let described = try ganttChart("gantt\naccTitle: Spoken\naccDescr: What it plans\nA : 2014-01-01, 1d")
        XCTAssertEqual(described.title, "Spoken")
        XCTAssertEqual(described.description, "What it plans")
    }

    func testTodaysLineFollowsTheMomentAndTimeZoneGiven() throws {
        let parsed = try XCTUnwrap(try? MermaidDiagramReader.read(chart, limits: .standard))
        guard case .ganttChart(let gantt) = parsed else { return XCTFail("A Gantt chart") }
        let utc = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let inside = ReadingGanttChart.diagram(source: chart, chart: gantt, typography: typography, now: Date(timeIntervalSince1970: 1_389_182_400),
                                               timeZone: utc)
        guard case .ganttChart(let drawn)? = inside else { return XCTFail("Drawn") }
        XCTAssertNotNil(drawn.layout.plot?.todayOffset)
        XCTAssertFalse(drawn.shapes.todayLine.isEmpty)
    }

    func testAChartWithAStatementNotDrawnOrADateNotReadStaysCode() {
        XCTAssertNil(ReadingDiagram(source: "gantt\nA : a, 2014-01-01, 1d\nclick a href \"https://example.com\"", typography: typography))
        XCTAssertNil(ReadingDiagram(source: "gantt\nA : vert, 2014-01-01, 1d", typography: typography))
        XCTAssertNil(ReadingDiagram(source: "gantt\nA : March 7 2014, 1d", typography: typography))
    }

    func testAChartThatCannotBeScheduledKeepsItsSourceAndWhy() throws {
        let source = "gantt\ndateFormat YYYY-MM-DD\nexcludes weekends,monday,tuesday,wednesday,thursday,friday\nForever : 2019-02-01, 7d"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .ganttLayout(.noDayLeftAfterExclusions(task: "Forever")))
        let unreadable = try XCTUnwrap(ReadingDiagram(source: "gantt\nNo colon here", typography: typography))
        guard case .unreadable(_, .reading(.invalidSyntax(line: 2, problem: .expectedTaskData))) = unreadable else { return XCTFail("Why") }
    }

    func testTheGanttChartsFailuresAreExplainedApart() {
        let failures: [ReadingDiagramFailure] = [
            .ganttLayout(.statementNotDrawn(.click)), .ganttLayout(.unreadableDate("x")), .ganttLayout(.noDayLeftAfterExclusions(task: "A")),
            .ganttLayout(.tooManyScheduledDays(limit: 1)), .reading(.invalidSyntax(line: 1, problem: .expectedTaskData)),
            .reading(.invalidSyntax(line: 1, problem: .taskWithoutEnd(task: "A"))),
            .reading(.invalidSyntax(line: 1, problem: .taskWithTooManyFields(task: "A"))),
        ]
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
    }
}
