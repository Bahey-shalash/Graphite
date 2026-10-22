import XCTest
@testable import MermaidDiagrams

/// Pele's Gantt measurements, with text of uniform width (the title 8 points a character at 16, rows 6 at 13, axis
/// dates 6 at 12: bars 24 points tall, rows 30, the axis 21), in UTC, on 2026-10-23 15:30.
final class GanttLayoutEngineTests: XCTestCase {
    private func time(_ year: Int64, _ month: Int64, _ day: Int64, _ hour: Int64 = 0) throws -> GanttTime {
        try GanttScheduling.time(year, month, day, hour)
    }

    private func laidOut(_ source: String, now: GanttTime? = nil) throws -> GanttLayout {
        let chart = try GanttChartReading.ganttChart(source)
        let zone = try GanttScheduling.zone("UTC")
        let moment = try now ?? GanttScheduling.now()
        let schedule = try GanttSchedule(chart: chart, now: moment, zone: zone, limits: .standard)
        let measurers = GanttMeasurers(title: UniformWidthTextMeasurer(), row: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 13, lineHeight: 20),
                                       axis: UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18))
        return GanttLayoutEngine.layout(chart, schedule: schedule.entries, now: moment, zone: zone, measurers: measurers, font: UniformWidthLayout.font)
    }

    private let documentationExample = """
    gantt
        title A Gantt Diagram
        dateFormat YYYY-MM-DD
        section Section
            A task          :a1, 2014-01-01, 30d
            Another task    :after a1, 20d
        section Another
            Task in Another :2014-01-12, 12d
            another task    :24d
    """

    func testThePlotSpansTheTasksBetweenTheSectionNamesAndRoomForTheDates() throws {
        let layout = try laidOut(documentationExample)
        let plot = try XCTUnwrap(layout.plot)
        // Left: the padding, then the widest section name (7 characters) and 24 points; right: half the widest date
        // (10 characters); the plot fills the rest of 800 points.
        XCTAssertEqual(plot.frame, CGRect(x: 74, y: 48, width: 688, height: 120))
        XCTAssertEqual(layout.size, CGSize(width: 800, height: 197))
        XCTAssertEqual(layout.title?.center, CGPoint(x: 400, y: 20))
    }

    func testEachTaskIsABarAcrossItsTimeWithItsTextInsideWhenItFits() throws {
        let plot = try XCTUnwrap(try laidOut(documentationExample).plot)
        let pointsPerDay = 688.0 / 50
        XCTAssertEqual(plot.tasks.count, 4)
        guard case .bar(let first) = plot.tasks[0].shape else { return XCTFail("A bar") }
        XCTAssertEqual(first.minX, 74, accuracy: 1e-9)
        XCTAssertEqual(first.width, 30 * pointsPerDay, accuracy: 1e-9)
        XCTAssertEqual(first.minY, 51)
        XCTAssertEqual(first.height, 24)
        XCTAssertEqual(plot.tasks[0].label.center.x, first.midX, accuracy: 1e-9)
        XCTAssertEqual(plot.tasks[0].label.center.y, 63)
        XCTAssertEqual(plot.tasks[0].labelColor, .background)
        XCTAssertEqual(plot.tasks[0].paint, GanttTaskPaint(fill: .accent, stroke: .accent))
        guard case .bar(let third) = plot.tasks[2].shape else { return XCTFail("A bar") }
        XCTAssertEqual(third.minX, 74 + 11 * pointsPerDay, accuracy: 1e-9)
        XCTAssertEqual(third.minY, 51 + 60)
    }

    func testTheAxisMarksEachWeekFromSundayAndTheSectionsAlternateTheirBands() throws {
        let plot = try XCTUnwrap(try laidOut(documentationExample).plot)
        let pointsPerDay = 688.0 / 50
        XCTAssertEqual(plot.gridLineOffsets.count, 7)
        XCTAssertEqual(plot.gridLineOffsets[0], 74 + 4 * pointsPerDay, accuracy: 1e-9, "Sunday 2014-01-05")
        let sundays = ["2014-01-05", "2014-01-12", "2014-01-19", "2014-01-26", "2014-02-02", "2014-02-09", "2014-02-16"]
        XCTAssertEqual(plot.axisDates.map(\.lines), sundays.map { sunday in [sunday] })
        XCTAssertEqual(plot.axisDates[0].center.y, 168 + 10.5 + 2)
        XCTAssertEqual(plot.sectionBands, [CGRect(x: 0, y: 48, width: 800, height: 60)])
        XCTAssertEqual(plot.sectionNames.map(\.lines), [["Section"], ["Another"]])
        XCTAssertEqual(plot.sectionNames.map(\.center), [CGPoint(x: 37, y: 78), CGPoint(x: 37, y: 138)])
        XCTAssertNil(plot.todayOffset, "Today is outside the chart")
    }

    func testTodaysLineRunsAtNowUnlessItIsOff() throws {
        let now = try time(2014, 1, 26, 12)
        let plot = try XCTUnwrap(try laidOut(documentationExample, now: now).plot)
        XCTAssertEqual(try XCTUnwrap(plot.todayOffset), 74 + 25.5 * 688 / 50, accuracy: 1e-9)
        XCTAssertNil(try laidOut(documentationExample + "\n    todayMarker off", now: now).plot?.todayOffset)
        XCTAssertNotNil(try laidOut(documentationExample + "\n    todayMarker stroke-width:5px", now: now).plot?.todayOffset)
    }

    func testAMilestoneIsADiamondAtTheMiddleOfItsTime() throws {
        let plot = try XCTUnwrap(try laidOut("gantt\ndateFormat YYYY-MM-DD\nA : a, 2014-01-01, 4d\nM : milestone, m, 2014-01-03, 0d").plot)
        guard case .milestone(let diamond) = plot.tasks[1].shape else { return XCTFail("A milestone") }
        XCTAssertEqual(diamond.midX, plot.frame.minX + plot.frame.width / 2, accuracy: 1e-9)
        XCTAssertEqual(diamond.size, CGSize(width: 24, height: 24))
        XCTAssertEqual(plot.tasks[1].label.center.x, diamond.maxX + 8 + 3, accuracy: 1e-9, "Its text after it")
    }

    func testTextTooLongForItsBarGoesAfterItOrBeforeIt() throws {
        let plot = try XCTUnwrap(try laidOut("gantt\ndateFormat YYYY-MM-DD\nLong task name : 2014-01-01, 1d\nShort : 2014-01-02, 9d\n"
                                             + "A much longer task name here : 2014-01-09, 1d").plot)
        guard case .bar(let first) = plot.tasks[0].shape, case .bar(let last) = plot.tasks[2].shape else { return XCTFail("Bars") }
        XCTAssertEqual(plot.tasks[0].label.center.x, first.maxX + 8 + 42, accuracy: 1e-9)
        XCTAssertEqual(plot.tasks[0].labelColor, .foreground)
        XCTAssertEqual(plot.tasks[2].label.center.x, last.minX - 8 - 84, accuracy: 1e-9, "No room after the last bar")
    }

    func testDoneActiveAndCriticalTasksTakeTheirPaints() throws {
        let plot = try XCTUnwrap(try laidOut("gantt\ndateFormat YYYY-MM-DD\nA : done, 2014-01-01, 10d\nB : active, crit, 2014-01-01, 10d\n"
                                             + "C : crit, 2014-01-01, 10d\nDone critical task beside its bar : crit, done, 2014-01-01, 1d").plot)
        XCTAssertEqual(plot.tasks.map(\.paint), [GanttTaskPaint(fill: .alternateSurface, stroke: .border),
                                                 GanttTaskPaint(fill: .faintCritical, stroke: .critical), GanttTaskPaint(fill: .critical, stroke: .critical),
                                                 GanttTaskPaint(fill: .alternateSurface, stroke: .critical)])
        XCTAssertEqual(plot.tasks.map(\.labelColor), [.foreground, .foreground, .background, .muted])
    }

    func testATaskWithoutAStartIsTextAtTheLeftAndATitleAloneHasNoPlot() throws {
        let plot = try XCTUnwrap(try laidOut("gantt\nWaiting : w, after x, 1d\nX : x, after w, 1d\nReady : 2014-01-01, 1d").plot)
        XCTAssertEqual(plot.tasks[0].shape, .unscheduled)
        XCTAssertEqual(plot.tasks[0].labelColor, .muted)
        XCTAssertEqual(plot.tasks[0].label.center.x, plot.frame.minX + 8 + 21)
        let titled = try laidOut("gantt\ntitle Nothing scheduled\nLoop : l, after l, 1d")
        XCTAssertNil(titled.plot)
        XCTAssertEqual(titled.size, CGSize(width: 17 * 8 + 16, height: 24 + 16))
    }

    func testTheTopAxisRepeatsTheDatesAboveAndExcludedDaysAreShaded() throws {
        let plain = try XCTUnwrap(try laidOut(documentationExample).plot)
        let topped = try XCTUnwrap(try laidOut(documentationExample + "\n    topAxis").plot)
        XCTAssertEqual(topped.frame.minY, plain.frame.minY + 21)
        XCTAssertEqual(topped.axisDates.count, 2 * plain.axisDates.count)
        let excluded = try XCTUnwrap(try laidOut("gantt\ndateFormat YYYY-MM-DD\nexcludes weekends\nA : 2014-01-01, 10d").plot)
        let pointsPerDay = excluded.frame.width / 14
        XCTAssertEqual(excluded.excludedDays.count, 2)
        XCTAssertEqual(excluded.excludedDays[0].minX, excluded.frame.minX + 3 * pointsPerDay, accuracy: 1e-6, "Saturday the 4th")
        XCTAssertEqual(excluded.excludedDays[0].width, 2 * pointsPerDay, accuracy: 0.01)
    }

    func testAChartSpanningNoTimePutsEverythingAtTheMiddle() throws {
        let plot = try XCTUnwrap(try laidOut("gantt\ndateFormat YYYY-MM-DD\nLaunch : milestone, 2014-01-01, 0d").plot)
        guard case .milestone(let diamond) = plot.tasks[0].shape else { return XCTFail("A milestone") }
        XCTAssertEqual(diamond.midX, plot.frame.midX)
        XCTAssertEqual(plot.gridLineOffsets, [plot.frame.midX])
    }

    func testAStatementNotDrawnYetRefusesTheChart() {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        XCTAssertThrowsError(try GanttLayoutEngine.layout(try GanttChartReading.ganttChart("gantt\nA : a, 2014-01-01, 1d\nclick a href \"x\""),
                                                          typography: typography, now: Date(timeIntervalSince1970: 0), timeZone: .gmt,
                                                          limits: .standard)) { error in
            XCTAssertEqual(error as? GanttLayoutError, .statementNotDrawn(.click))
        }
    }
}
