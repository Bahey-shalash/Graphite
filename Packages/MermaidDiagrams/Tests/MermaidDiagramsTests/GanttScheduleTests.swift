import XCTest
@testable import MermaidDiagrams

/// The schedules of Mermaid 12.1.0's Gantt database spec (`ganttDb.spec.ts`, as Pele ports it in `tests/compat/gantt`),
/// in Paris unless a test names another time zone, on a given day.
final class GanttScheduleTests: XCTestCase {
    private func time(_ year: Int64, _ month: Int64, _ day: Int64, _ hour: Int64 = 0, _ minute: Int64 = 0, _ second: Int64 = 0) throws -> GanttTime {
        try GanttScheduling.time(year, month, day, hour, minute, second)
    }

    private func entries(_ body: String, dateFormat: String = "YYYY-MM-DD") throws -> [GanttSchedule.Entry] {
        try GanttScheduling.schedule("gantt\ndateFormat \(dateFormat)\n" + body).entries
    }

    func testFixedDatesAndDurationsGiveTheEnd() throws {
        let cases: [(String, GanttTime)] = [
            ("id1,2013-01-01,2013-01-12", try time(2013, 1, 12)), ("id1,2013-01-01,2d", try time(2013, 1, 3)),
            ("id1,2013-01-01,2h", try time(2013, 1, 1, 2)), ("id1,2013-01-01,2m", try time(2013, 1, 1, 0, 2)),
            ("id1,2013-01-01,2s", try time(2013, 1, 1, 0, 0, 2)), ("id1,2013-01-01,2w", try time(2013, 1, 15)),
            ("2013-01-01,2013-01-12", try time(2013, 1, 12)), ("2013-01-01,4d", try time(2013, 1, 5)),
        ]
        for (data, end) in cases {
            let entry = try XCTUnwrap(try entries("section testa1\ntest1 : \(data)").first)
            XCTAssertEqual(entry.start, try time(2013, 1, 1), data)
            XCTAssertEqual(entry.end, end, data)
        }
    }

    func testATaskStartsAfterOthersOrWhereTheTaskBeforeItEnds() throws {
        let cases: [(String, GanttTime, GanttTime?)] = [
            ("id2,after id1,1d", try time(2013, 1, 15), nil), ("id2,after id3,1d", try time(2026, 10, 23), nil),
            ("after id1,1d", try time(2013, 1, 15), nil), ("2013-01-26", try time(2013, 1, 15), try time(2013, 1, 26)),
            ("2d", try time(2013, 1, 15), try time(2013, 1, 17)),
        ]
        for (data, start, end) in cases {
            let second = try entries("section testa1\ntest1 : id1,2013-01-01,2w\ntest2 : \(data)")[1]
            XCTAssertEqual(second.start, start, data)
            if let end { XCTAssertEqual(second.end, end, data) }
        }
    }

    func testMillisecondsInUnixTime() throws {
        let body = "section testa1\ntest1 : id1,0,20ms\ntest2 : id2,after id1,5ms\nsection testa2\ntest3 : id3,20,10ms\ntest4 : id4,after id3,0.005s"
        let schedule = try GanttScheduling.schedule("gantt\ndateFormat x\n" + body, zone: try GanttScheduling.zone("UTC"))
        XCTAssertEqual(schedule.entries.map { entry in entry.start?.milliseconds }, [0, 20, 20, 30])
        XCTAssertEqual(schedule.entries.map { entry in entry.end?.milliseconds }, [20, 25, 30, 35])
    }

    func testReferencesReachAcrossSectionsAndForward() throws {
        let starts = try entries("section sec1\ntest1 : id1,2013-01-01,2w\ntest2 : id2,after id3,1d\nsection sec2\ntest3 : id3,after id1,2d")
        XCTAssertEqual(starts[1].start, try time(2013, 1, 17))
        XCTAssertEqual(starts[1].end, try time(2013, 1, 18))
        XCTAssertEqual(starts[2].start, try time(2013, 1, 15))
        XCTAssertEqual(starts[2].end, try time(2013, 1, 17))
        let ends = try entries("section sec1\ntask1 : id1,2013-01-01,until id3\nsection sec2\ntask2 : id2,2013-01-10,until id3\ntask3 : id3,2013-02-01,2d")
        XCTAssertEqual(ends[0].end, try time(2013, 2, 1))
        XCTAssertEqual(ends[1].start, try time(2013, 1, 10))
        XCTAssertEqual(ends[1].end, try time(2013, 2, 1))
    }

    func testSeveralReferencesTakeTheLatestEndOrTheEarliestStart() throws {
        let after = try entries("section sec1\ntask1 : id1,after id2 id3 id4,1d\ntask2 : id2,2013-01-01,1d\ntask3 : id3,2013-02-01,3d\n"
                                + "task4 : id4,2013-02-01,2d")
        XCTAssertEqual(after[0].end, try time(2013, 2, 5))
        let until = try entries("section sec1\ntask1 : id1,2013-01-01,until id2 id3 id4\ntask2 : id2,2013-01-11,1d\ntask3 : id3,2013-02-10,1d\n"
                                + "task4 : id4,2013-02-12,1d")
        XCTAssertEqual(until[0].end, try time(2013, 1, 11))
    }

    func testExcludedDaysMoveDurationsAndNotWrittenEnds() throws {
        let schedule = try entries("""
        excludes weekends 2019-02-06,friday
        section weekends skip test
        test1 : id1,2019-02-01,1d
        test2 : id2,after id1,2d
        test3 : id3,after id2,7d
        test4 : id4,2019-02-01,2019-02-20
        test5 : id5,after id4,1d
        section full ending task on last day
        test6 : id6,2019-02-13,2d
        test7 : id7,after id6,1d
        """)
        let expected: [(GanttTime, GanttTime, GanttTime?)] = [
            (try time(2019, 2, 1), try time(2019, 2, 4), try time(2019, 2, 2)), (try time(2019, 2, 4), try time(2019, 2, 7), try time(2019, 2, 6)),
            (try time(2019, 2, 7), try time(2019, 2, 20), try time(2019, 2, 20)), (try time(2019, 2, 1), try time(2019, 2, 20), nil),
            (try time(2019, 2, 20), try time(2019, 2, 21), try time(2019, 2, 21)), (try time(2019, 2, 13), try time(2019, 2, 18), try time(2019, 2, 15)),
            (try time(2019, 2, 18), try time(2019, 2, 19), nil),
        ]
        for (index, (start, end, drawnEnd)) in expected.enumerated() {
            XCTAssertEqual(schedule[index].start, start, "test\(index + 1)")
            XCTAssertEqual(schedule[index].end, end, "test\(index + 1)")
            if index != 6 { XCTAssertEqual(schedule[index].drawnEnd, drawnEnd, "test\(index + 1)") }
        }
    }

    func testAWeekendFromFridayLeavesOutFridayAndSaturday() throws {
        let entry = try XCTUnwrap(try entries("excludes weekends\nweekend friday\nsection s\ntest1 : id1,2024-02-28, 3d").first)
        XCTAssertEqual(entry.end, try time(2024, 3, 4))
    }

    func testExcludingEveryDayIsRefusedAndLeavingFridayIsNot() {
        XCTAssertEqual(GanttScheduling.scheduleError("gantt\ndateFormat YYYY-MM-DD\nexcludes weekends,monday,tuesday,wednesday,thursday,friday\n"
                                                     + "weekend saturday\nsection s\ntest1 : id1,2019-02-01,7d"),
                       .noDayLeftAfterExclusions(task: "test1"))
        XCTAssertNil(GanttScheduling.scheduleError("gantt\ndateFormat YYYY-MM-DD\nexcludes weekends,monday,tuesday,wednesday,thursday\n"
                                                   + "section s\ntest1 : id1,2019-02-01,7d"))
    }

    func testTheDocumentationsOrderOfTasksIsKept() throws {
        let schedule = try entries("""
        section A section
        Completed task : done,    des1, 2014-01-06,2014-01-08
        Active task : active,  des2, 2014-01-09, 3d
        Future task : des3, after des2, 5d
        section Critical tasks
        Completed task in the critical line : crit, done, 2014-01-06,24h
        Implement parser and jison : crit, done, after des1, 2d
        Create tests for parser : crit, active, 3d
        section Documentation
        Describe gantt syntax : active, a1, after des1, 3d
        Add gantt diagram to demo page : after a1  , 20h
        Add another diagram to demo page : doc1, after a1  , 48h
        section Last section
        Describe gantt syntax : after doc1, 3d
        Add gantt diagram to demo page : 20h
        Add another diagram to demo page : 48h
        """)
        let starts = [try time(2014, 1, 6), try time(2014, 1, 9), try time(2014, 1, 12), try time(2014, 1, 6), try time(2014, 1, 8), try time(2014, 1, 10),
                      try time(2014, 1, 8), try time(2014, 1, 11), try time(2014, 1, 11), try time(2014, 1, 13), try time(2014, 1, 16),
                      try time(2014, 1, 16, 20)]
        let ends = [try time(2014, 1, 8), try time(2014, 1, 12), try time(2014, 1, 17), try time(2014, 1, 7), try time(2014, 1, 10), try time(2014, 1, 13),
                    try time(2014, 1, 11), try time(2014, 1, 11, 20), try time(2014, 1, 13), try time(2014, 1, 16), try time(2014, 1, 16, 20),
                    try time(2014, 1, 18, 20)]
        XCTAssertEqual(schedule.map(\.start), starts)
        XCTAssertEqual(schedule.map(\.end), ends)
    }

    func testAnEndOnTheThirtyFirstStaysThere() throws {
        let schedule = try entries("section s\ntest1 : id1,2019-09-30,11d\ntest2 : id2,after id1,20d")
        XCTAssertEqual(schedule[0].end, try time(2019, 10, 11))
        XCTAssertEqual(schedule[1].start, try time(2019, 10, 11))
        XCTAssertEqual(schedule[1].end, try time(2019, 10, 31))
        XCTAssertNil(schedule[1].drawnEnd)
    }

    func testADayIsADayOnTheWallClockAcrossADaylightSavingChange() throws {
        let zone = try GanttScheduling.zone("America/Los_Angeles")
        let entry = try XCTUnwrap(try GanttScheduling.schedule("gantt\ndateFormat YYYY-MM-DD\nsection s\ndaylight savings day : id1,2020-11-01,1d",
                                                               zone: zone).entries.first)
        let start = try XCTUnwrap(entry.start)
        let end = try XCTUnwrap(entry.end)
        XCTAssertEqual(end, try time(2020, 11, 2))
        XCTAssertEqual(zone.unixMilliseconds(of: start), 1_604_214_000_000, "2020-11-01T07:00:00Z")
        XCTAssertEqual(zone.unixMilliseconds(of: end) - zone.unixMilliseconds(of: start), 25 * GanttTime.millisecondsPerHour)
    }

    func testInclusiveEndDatesAddADayToWrittenEnds() throws {
        let schedule = try entries("inclusiveEndDates\ntest1 : id1,2019-02-01,1d\ntest2 : id2,2019-02-01,2019-02-03")
        XCTAssertEqual(schedule[0].end, try time(2019, 2, 2))
        XCTAssertEqual(schedule[1].end, try time(2019, 2, 4))
        XCTAssertTrue(schedule[1].hasWrittenEnd)
        XCTAssertNil(schedule[1].drawnEnd)
    }

    func testDatesThatAreNoneOfTheFormsReadAreRefusedByTheirText() {
        XCTAssertEqual(GanttScheduling.scheduleError("gantt\ndateFormat YYYYMMDD\ntest1 : id1,202304,1d"), .unreadableDate("202304"))
        XCTAssertEqual(GanttScheduling.scheduleError("gantt\ndateFormat ss\nRTT : rtt, 0, 20"), .unreadableDate("0"))
    }

    func testAYearWrittenShortIsReadAsJavaScriptReadsIt() throws {
        let schedule = try entries("section Vacation\nLondon Trip 1 : 2024-12-01, 7d\nLondon Trip 2 : 202-12-01, 7d")
        XCTAssertEqual(schedule[0].start?.year, 2024)
        XCTAssertEqual(schedule[1].start, try time(202, 12, 1))
    }

    func testUnknownReferencesStartTodayAndAnUnreadableEndGivesNoLength() throws {
        let unknown = try entries("task1 : id1,2013-01-01,2d\ntask2 : id2,after m1,1d\ntask3 : id3,2013-01-01,until m2")
        XCTAssertEqual(unknown[1].start, try time(2026, 10, 23))
        XCTAssertEqual(unknown[2].end, try time(2026, 10, 23))
        let milestone = try XCTUnwrap(try entries("M1 : milestone, 2023-01-01, m1").first)
        XCTAssertEqual(milestone.end, milestone.start)
    }

    func testATaskWaitingOnACycleIsNotScheduled() throws {
        let schedule = try entries("a : a, after b, 1d\nb : b, after a, 1d\nc : c, 2014-01-01, 1d")
        XCTAssertEqual(schedule.map(\.isScheduled), [false, false, true])
        XCTAssertNil(schedule[0].start)
    }

    func testSteppingPastTheDayLimitIsRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumScheduledDayCount = 100
        XCTAssertEqual(GanttScheduling.scheduleError("gantt\ndateFormat YYYY-MM-DD\nexcludes weekends\nlong : 2014-01-01, 1000d", limits: limits),
                       .tooManyScheduledDays(limit: 100))
    }
}
