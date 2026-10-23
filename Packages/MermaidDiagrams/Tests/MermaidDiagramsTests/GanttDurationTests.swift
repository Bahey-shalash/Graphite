import XCTest
@testable import MermaidDiagrams

/// Durations as Mermaid's Gantt database reads them (`ganttDb.spec.ts`) and its date library adds them (Pele's
/// `tests/gantt/dates.test.ts`).
final class GanttDurationTests: XCTestCase {
    private func time(_ year: Int64, _ month: Int64, _ day: Int64) throws -> GanttTime {
        try GanttScheduling.time(year, month, day)
    }

    private func adding(_ text: String, to start: GanttTime) throws -> GanttTime? {
        try XCTUnwrap(GanttDuration(text), text).added(to: start)
    }

    func testDurationsReadTheirAmountAndUnit() {
        XCTAssertEqual(GanttDuration("1d"), GanttDuration(amount: 1, unit: .days))
        XCTAssertEqual(GanttDuration("2w"), GanttDuration(amount: 2, unit: .weeks))
        XCTAssertEqual(GanttDuration("1ms"), GanttDuration(amount: 1, unit: .milliseconds))
        XCTAssertEqual(GanttDuration("0.1s"), GanttDuration(amount: 0.1, unit: .seconds))
        XCTAssertEqual(GanttDuration("1.5d"), GanttDuration(amount: 1.5, unit: .days))
        XCTAssertEqual(GanttDuration(" 3M "), GanttDuration(amount: 3, unit: .months))
        XCTAssertEqual(GanttDuration("500ms"), GanttDuration(amount: 500, unit: .milliseconds))
        for text in ["1f", "3dX", "-1d", "d", ".5d", "1.d", ""] { XCTAssertNil(GanttDuration(text), text) }
    }

    func testDaysAndWeeksAreWholeCalendarDays() throws {
        XCTAssertEqual(try adding("1d", to: try time(2020, 11, 1)), try time(2020, 11, 2))
        XCTAssertEqual(try adding("2d", to: try time(2024, 3, 9)), try time(2024, 3, 11))
        XCTAssertEqual(try adding("2w", to: try time(2013, 1, 1)), try time(2013, 1, 15))
        XCTAssertEqual(try adding("1.5d", to: try time(2013, 1, 1)), try time(2013, 1, 3))
        XCTAssertEqual(try adding("0.4d", to: try time(2013, 1, 1)), try time(2013, 1, 1))
        XCTAssertEqual(try adding("0.5w", to: try time(2013, 1, 1)), try time(2013, 1, 5))
    }

    func testSmallerUnitsAreExact() throws {
        let start = try time(2013, 1, 1)
        for (text, milliseconds) in [("2h", 7_200_000), ("2m", 120_000), ("0.005s", 5), ("20ms", 20)] as [(String, Int64)] {
            XCTAssertEqual(try adding(text, to: start)?.milliseconds, start.milliseconds + milliseconds, text)
        }
    }

    func testMonthsAndYearsKeepToTheEndOfAShorterMonth() throws {
        XCTAssertEqual(try adding("1M", to: try time(2024, 1, 31)), try time(2024, 2, 29))
        XCTAssertEqual(try adding("2M", to: try time(2023, 12, 31)), try time(2024, 2, 29))
        XCTAssertEqual(try adding("11M", to: try time(2024, 3, 30)), try time(2025, 2, 28))
        XCTAssertEqual(try adding("1y", to: try time(2024, 2, 29)), try time(2025, 2, 28))
        XCTAssertEqual(try adding("1.5M", to: try time(2024, 1, 15)), try time(2024, 2, 15))
    }

    func testADurationPastTheRangeOfDatesGivesNoDate() throws {
        XCTAssertNil(try adding("99999999y", to: try time(2024, 1, 1)))
        XCTAssertNil(try adding("99999999999999999999d", to: try time(2024, 1, 1)))
    }
}
