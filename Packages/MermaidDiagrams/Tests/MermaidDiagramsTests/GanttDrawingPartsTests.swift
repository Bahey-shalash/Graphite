import XCTest
@testable import MermaidDiagrams

final class GanttDrawingPartsTests: XCTestCase {
    private func parts(_ source: String, now: GanttTime? = nil) throws -> (GanttLayout, GanttDrawingParts) {
        let chart = try GanttChartReading.ganttChart(source)
        let zone = try GanttScheduling.zone("UTC")
        let moment = try now ?? GanttScheduling.now()
        let schedule = try GanttSchedule(chart: chart, now: moment, zone: zone, limits: .standard)
        let measurers = GanttMeasurers(title: UniformWidthTextMeasurer(), row: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 13, lineHeight: 20),
                                       axis: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18))
        let layout = GanttLayoutEngine.layout(chart, schedule: schedule.entries, now: moment, zone: zone, measurers: measurers, font: UniformWidthLayout.font)
        return (layout, GanttDrawingParts(layout: layout))
    }

    func testTasksAreGroupedByFillAndOutline() throws {
        let (_, parts) = try parts("gantt\ndateFormat YYYY-MM-DD\nA : 2014-01-01, 2d\nB : 2014-01-02, 2d\nC : crit, done, 2014-01-03, 2d\n"
                                   + "D : active, 2014-01-04, 2d\nE : w, after w, 1d")
        XCTAssertEqual(Set(parts.taskFills.keys), [.accent, .alternateSurface, .faintAccent])
        XCTAssertEqual(Set(parts.taskOutlines.keys), [.accent, .critical])
        XCTAssertEqual(parts.taskTexts[.muted]?.map(\.lines), [["E"]], "The task without a start")
        XCTAssertEqual(parts.taskTexts.values.map(\.count).reduce(0, +), 5)
    }

    func testANarrowBarKeepsItsFrameAndAMilestoneIsADiamond() throws {
        let bar = try XCTUnwrap(GanttDrawingParts.outline(of: .bar(CGRect(x: 10, y: 10, width: 2, height: 24))))
        XCTAssertEqual(bar.boundingBoxOfPath, CGRect(x: 10, y: 10, width: 2, height: 24))
        let diamond = try XCTUnwrap(GanttDrawingParts.outline(of: .milestone(CGRect(x: 0, y: 0, width: 24, height: 24))))
        XCTAssertTrue(diamond.contains(CGPoint(x: 12, y: 12)))
        XCTAssertFalse(diamond.contains(CGPoint(x: 2, y: 2)))
        XCTAssertNil(GanttDrawingParts.outline(of: .unscheduled))
    }

    func testTodaysLineAndMarkAreThereOnlyWhenTodayIsInTheChart() throws {
        let source = "gantt\ndateFormat YYYY-MM-DD\nA : 2014-01-01, 10d"
        let (inside, today) = try parts(source, now: try GanttScheduling.time(2014, 1, 5))
        XCTAssertEqual(today.todayLine.boundingBoxOfPath.minX, try XCTUnwrap(inside.plot?.todayOffset), accuracy: 1e-9)
        XCTAssertFalse(today.todayMark.isEmpty)
        let (_, later) = try parts(source)
        XCTAssertTrue(later.todayLine.isEmpty)
        XCTAssertTrue(later.todayMark.isEmpty)
    }

    func testTheGridRunsDownTheRowsAndTheAxisLineIsBelowAndAboveWithTopAxis() throws {
        let (layout, parts) = try parts("gantt\ndateFormat YYYY-MM-DD\ntopAxis\nA : 2014-01-01, 10d")
        let plot = try XCTUnwrap(layout.plot)
        XCTAssertEqual(parts.gridLines.boundingBoxOfPath.minY, plot.frame.minY)
        XCTAssertEqual(parts.gridLines.boundingBoxOfPath.maxY, plot.frame.maxY)
        XCTAssertEqual(parts.axisLines.boundingBoxOfPath, plot.frame)
        XCTAssertEqual(parts.axisDates.count, plot.axisDates.count)
    }

    func testAChartWithNoScheduledTaskHasOnlyItsTitle() throws {
        let (_, parts) = try parts("gantt\ntitle Waiting\nA : a, after a, 1d")
        XCTAssertEqual(parts.title?.lines, ["Waiting"])
        XCTAssertTrue(parts.taskFills.isEmpty)
        XCTAssertTrue(parts.gridLines.isEmpty)
        XCTAssertTrue(parts.axisLines.isEmpty)
    }
}
