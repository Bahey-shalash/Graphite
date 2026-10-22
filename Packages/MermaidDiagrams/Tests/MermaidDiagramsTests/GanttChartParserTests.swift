import XCTest
@testable import MermaidDiagrams

/// The inputs of Mermaid 12.1.0's Gantt parser spec (`gantt.spec.js`, as Pele ports it in `tests/compat/gantt`),
/// the tasks of its database spec (`ganttDb.spec.ts`), Mermaid's documentation examples, and the errors.
final class GanttChartParserTests: XCTestCase {
    private func ganttChart(_ source: String) throws -> GanttChart {
        try GanttChartReading.ganttChart(source)
    }

    private func readError(_ source: String, limits: MermaidDiagramLimits = .standard) -> MermaidDiagramReadError? {
        GanttChartReading.readError(source, limits: limits)
    }

    private let header = "gantt\ndateFormat YYYY-MM-DD\ntitle Adding gantt diagram functionality to mermaid\n"

    // MARK: Mermaid's parser spec

    func testSettingsRead() throws {
        XCTAssertEqual(try ganttChart("gantt\ndateFormat yyyy-mm-dd").dateFormat, "yyyy-mm-dd")
        XCTAssertTrue(try ganttChart("gantt\ndateFormat yyyy-mm-dd\ninclusiveEndDates").isEndDateInclusive)
        XCTAssertEqual(try ganttChart("gantt\naxisFormat %H:%M\ntopAxis").axisFormat, "%H:%M")
        XCTAssertTrue(try ganttChart("gantt\ntopAxis").showsTopAxis)
    }

    func testTitlesTakeSemicolonsAndNumberSigns() throws {
        XCTAssertEqual(try ganttChart("gantt\ndateFormat yyyy-mm-dd\ntitle Adding gantt diagram functionality to mermaid").title,
                       "Adding gantt diagram functionality to mermaid")
        XCTAssertEqual(try ganttChart("gantt\ndateFormat yyyy-mm-dd\ntitle ;Gantt diagram titles support semicolons").title,
                       ";Gantt diagram titles support semicolons")
        XCTAssertEqual(try ganttChart("gantt\ndateFormat yyyy-mm-dd\ntitle #Gantt diagram titles support hashtags").title,
                       "#Gantt diagram titles support hashtags")
    }

    func testExcludesAreMergedAcrossLinesInTheirOrder() throws {
        XCTAssertEqual(try ganttChart("gantt\ndateFormat yyyy-mm-dd\nexcludes weekdays 2019-02-01").excludedDays, ["weekdays", "2019-02-01"])
        let chart = try ganttChart("""
        gantt
        dateFormat DD-MM-YYYY
        excludes weekends
        %% week 7 is winter break
        excludes 10-02-2025 11-02-2025 12-02-2025
        %% workers holiday 1 maj
        excludes 01-05-2025
        excludes Weekends,2019-02-06
        """)
        XCTAssertEqual(chart.excludedDays, ["weekends", "10-02-2025", "11-02-2025", "12-02-2025", "01-05-2025", "2019-02-06"])
        XCTAssertEqual(try ganttChart("gantt\nincludes 2019-02-06\nincludes 2019-02-07,2019-02-08").includedDays, ["2019-02-06", "2019-02-07", "2019-02-08"])
    }

    func testTheTodayMarkerIsOffOrStyled() throws {
        XCTAssertEqual(try ganttChart(header + "excludes weekdays 2019-02-01\ntodayMarker off").todayMarker, .hidden)
        XCTAssertEqual(try ganttChart("gantt\ntodayMarker stroke-width:5px,stroke:#00f,opacity:0.5").todayMarker,
                       .styled("stroke-width:5px,stroke:#00f,opacity:0.5"))
        XCTAssertEqual(try ganttChart("gantt").todayMarker, .standard)
    }

    func testSectionsTakeSemicolonsNumberSignsAndLineBreakTags() throws {
        for name in ["Documentation", ";Documentation", "#Documentation", "Line1<br>Line2<br/>Line3</br />Line4<br\t/>Line5"] {
            XCTAssertEqual(try ganttChart(header + "excludes weekdays 2019-02-01\nsection \(name)").sections, [name], name)
        }
    }

    func testATaskReadsItsIdentifierDatesAndText() throws {
        for prefix in ["", ";", "#"] {
            let task = try XCTUnwrap(try ganttChart(header + "section Documentation\n\(prefix)Design jison grammar:des1, 2014-01-01, 2014-01-04").tasks.first)
            XCTAssertEqual(task.name, prefix + "Design jison grammar")
            XCTAssertEqual(task.identifier, "des1")
            XCTAssertEqual(task.startText, "2014-01-01")
            XCTAssertEqual(task.endText, "2014-01-04")
            XCTAssertEqual(task.section, "Documentation")
        }
    }

    func testTasksRelativeToOthersKeepTheirReferences() throws {
        let chart = try ganttChart(header + "section Documentation\ntask A: a, 2024-01-27, 2024-01-28\ntask B: b, after a, 2024-01-30\n"
                                   + "task C: c, 2024-01-20, until a\ntask D: d, after c, until b")
        XCTAssertEqual(chart.tasks.map(\.identifier), ["a", "b", "c", "d"])
        XCTAssertEqual(chart.tasks.map(\.startText), ["2024-01-27", "after a", "2024-01-20", "after c"])
        XCTAssertEqual(chart.tasks.map(\.endText), ["2024-01-28", "2024-01-30", "until a", "until b"])
        XCTAssertEqual(chart.tasks.map(\.previousTaskIdentifier), [nil, "a", "b", "c"])
    }

    func testTagsReadInAnyCombination() throws {
        let cases: [(String, [Bool])] = [
            ("milestone", [true, false, false, false]), ("done", [false, true, false, false]), ("crit", [false, false, true, false]),
            ("active", [false, false, false, true]), ("crit,milestone,done", [true, true, true, false]),
        ]
        for (tags, expected) in cases {
            let task = try XCTUnwrap(try ganttChart(header + "section Documentation\ntest task:\(tags), 2014-01-01, 2014-01-04").tasks.first)
            XCTAssertEqual([task.isMilestone, task.isDone, task.isCritical, task.isActive], expected, tags)
            XCTAssertEqual(task.startText, "2014-01-01", tags)
        }
    }

    func testClickIsReadAndNotDrawn() throws {
        let chart = try ganttChart("gantt\ndateFormat  YYYY-MM-DD\nsection Clickable\nVisit mermaidjs           :active, cl1, 2014-01-07, 3d\n"
                                   + "Calling a callback        :cl2, after cl1, 3d\n\nclick cl1 href \"https://mermaidjs.github.io/\"\n"
                                   + "click cl2 call ganttTestClick(\"test0\", test1, test2)\n")
        XCTAssertEqual(chart.statementsNotDrawn, [.click])
        XCTAssertEqual(chart.tasks.count, 2)
        for identifier in ["__proto__", "constructor"] {
            let linked = try ganttChart("gantt\n    dateFormat YYYY-MM-DD\n    section Section\n    A task :\(identifier), 2024-10-01, 3d\n"
                                        + "    click \(identifier) href \"https://mermaid.js.org/\"\n    ")
            XCTAssertEqual(linked.tasks.first?.identifier, identifier)
        }
    }

    func testAccessibilityTitleAndDescriptionRead() throws {
        let chart = try ganttChart("gantt\n       accTitle: Gantt Diagram\n       accDescr: Tasks for Q4\n       dateFormat  YYYY-MM-DD\n"
                                   + "       section Section\n       A task :a1, 2014-01-01, 30d\n")
        XCTAssertEqual(chart.accessibilityTitle, "Gantt Diagram")
        XCTAssertEqual(chart.accessibilityDescription, "Tasks for Q4")
        let multiline = try ganttChart("gantt\n       accTitle: Gantt Diagram\n       accDescr {\n         Tasks for Q4 row1\nrow2\n       }\n"
                                       + "       dateFormat  YYYY-MM-DD\n       section Section\n       A task :a1, 2014-01-01, 30d\n")
        XCTAssertEqual(multiline.accessibilityDescription, "Tasks for Q4 row1\nrow2")
        XCTAssertEqual(multiline.tasks.count, 1)
    }

    func testTheWeekdayAndTheWeekendRead() throws {
        for day in ["monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday"] {
            XCTAssertNoThrow(try ganttChart("gantt\nweekday \(day)"), day)
        }
        XCTAssertEqual(try ganttChart("gantt\nweekend friday").weekendStart, .friday)
        XCTAssertEqual(try ganttChart("gantt\nweekend saturday").weekendStart, .saturday)
    }

    // MARK: Mermaid's documentation examples

    func testTheDocumentationsChartWithEveryKindOfTaskReads() throws {
        let chart = try ganttChart("""
        gantt
            dateFormat  YYYY-MM-DD
            title       Adding GANTT diagram functionality to mermaid
            excludes    weekends

            section A section
            Completed task            :done,    des1, 2014-01-06,2014-01-08
            Active task               :active,  des2, 2014-01-09, 3d
            Future task               :         des3, after des2, 5d

            section Critical tasks
            Completed task in the critical line :crit, done, 2014-01-06,24h
            Create tests for parser             :crit, active, 3d
            Add to mermaid                      :until isadded
            Functionality added                 :milestone, isadded, 2014-01-25, 0d

            section Documentation
            Add gantt diagram to demo page      :after a1  , 20h
        """)
        XCTAssertEqual(chart.title, "Adding GANTT diagram functionality to mermaid")
        XCTAssertEqual(chart.excludedDays, ["weekends"])
        XCTAssertEqual(chart.sections, ["A section", "Critical tasks", "Documentation"])
        XCTAssertEqual(chart.tasks.map(\.identifier), ["des1", "des2", "des3", "task1", "task2", "task3", "isadded", "task4"])
        XCTAssertEqual(chart.tasks.map(\.startText), ["2014-01-06", "2014-01-09", "after des2", "2014-01-06", nil, nil, "2014-01-25", "after a1"])
        XCTAssertEqual(chart.tasks.map(\.endText), ["2014-01-08", "3d", "5d", "24h", "3d", "until isadded", "0d", "20h"])
        XCTAssertEqual(chart.tasks.filter(\.isMilestone).map(\.name), ["Functionality added"])
        XCTAssertEqual(chart.tasks[3].section, "Critical tasks")
        XCTAssertTrue(chart.statementsNotDrawn.isEmpty)
    }

    func testTimesAVerticalMarkerATickIntervalAndItsWeekdayRead() throws {
        let times = try ganttChart("gantt\n    dateFormat HH:mm\n    axisFormat %H:%M\n    Initial milestone : milestone, m1, 17:49, 2m\n    Task A : 10m")
        XCTAssertEqual(times.tasks.map(\.endText), ["2m", "10m"])
        let marked = try ganttChart("gantt\n    dateFormat HH:mm\n    Initial vert : vert, v1, 17:30, 2m\n    Task A : 3m")
        XCTAssertEqual(marked.statementsNotDrawn, [.verticalMarker])
        let ticked = try ganttChart("gantt\n  tickInterval 1week\n  weekday monday")
        XCTAssertEqual(ticked.tickInterval, "1week")
        XCTAssertEqual(ticked.weekStart, .monday)
        XCTAssertTrue(ticked.statementsNotDrawn.isEmpty)
    }

    // MARK: Graphite's cases

    func testKeywordsReadInAnyCaseAndStatementsMayFollowTheKeyword() throws {
        let chart = try ganttChart("gantt DATEFORMAT YYYY\nTitle Upper\nSECTION One\nTask : 2014, 1d")
        XCTAssertEqual(chart.dateFormat, "YYYY")
        XCTAssertEqual(chart.title, "Upper")
        XCTAssertEqual(chart.sections, ["One"])
    }

    func testTasksWithoutAnIdentifierAreNumberedInOrder() throws {
        let chart = try ganttChart("gantt\nsection A\nOne : 2014-01-01, 1d\nTwo : a, 2014-01-02, 1d\nThree : 1d\nsection B\nFour : 2d")
        XCTAssertEqual(chart.tasks.map(\.identifier), ["task1", "a", "task2", "task3"])
        XCTAssertEqual(chart.tasks.map(\.previousTaskIdentifier), [nil, "task1", "a", "task2"])
        XCTAssertEqual(chart.tasks.map(\.section), ["A", "A", "A", "B"])
    }

    func testCommentsStartWithAPercentSign() throws {
        let chart = try ganttChart("gantt\n%% a comment\n% a lone sign\nx% a character then the sign\nTask : 1d %% after a task's data")
        XCTAssertEqual(chart.tasks.count, 1)
        XCTAssertEqual(chart.tasks.first?.endText, "1d %% after a task's data", "A task's data runs to #, ; or the end of the line")
    }

    func testASettingEndsAtASemicolonAndTheRestIsTheNextStatement() throws {
        let chart = try ganttChart("gantt\naxisFormat %Y;Task A: 1d")
        XCTAssertEqual(chart.axisFormat, "%Y")
        XCTAssertEqual(chart.tasks.first?.name, ";Task A")
    }

    func testATaskWithoutItsColonOrDataIsReportedOnItsLine() {
        XCTAssertEqual(readError("gantt\nsection A\nJust words"), .invalidSyntax(line: 3, problem: .expectedTaskData))
        XCTAssertEqual(readError("gantt\nTask :\nOther : 1d"), .invalidSyntax(line: 2, problem: .expectedTaskData))
        XCTAssertEqual(readError("gantt\ndateFormat"), .invalidSyntax(line: 2, problem: .expectedTaskData), "A setting without its value")
    }

    func testATaskNeedsAnEndAndAtMostThreeFields() {
        XCTAssertEqual(readError("gantt\nTask : done, crit"), .invalidSyntax(line: 2, problem: .taskWithoutEnd(task: "Task")))
        XCTAssertEqual(readError("gantt\n Task : a, 2014-01-01, 1d, more"), .invalidSyntax(line: 2, problem: .taskWithTooManyFields(task: "Task")))
    }

    func testWhatCannotStartAStatementIsUnexpected() {
        XCTAssertEqual(readError("gantt\n%%{init: {}}%%"), .invalidSyntax(line: 2, problem: .unexpectedText("%%{init: {}}%%")))
        XCTAssertEqual(readError("gantt\n2014-01-01 : 1d"), .invalidSyntax(line: 2, problem: .unexpectedText("2014-01-01 : 1d")))
        XCTAssertEqual(readError("gantt\n: 1d"), .invalidSyntax(line: 2, problem: .unexpectedText(": 1d")))
        XCTAssertEqual(readError("gantt\ngantt"), .invalidSyntax(line: 2, problem: .unexpectedText("gantt")))
        XCTAssertEqual(readError("gantt\naccDescription old style"), .invalidSyntax(line: 2, problem: .unexpectedText("accDescription old style")))
        XCTAssertEqual(readError("gantt\naccDescr {\nnever closed"), .invalidSyntax(line: 2, problem: .unclosedAccessibilityDescription))
    }

    func testTasksPastTheNodeLimitAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 2
        XCTAssertNil(readError("gantt\nA : 1d\nB : 1d", limits: limits))
        XCTAssertEqual(readError("gantt\nA : 1d\nB : 1d\nC : 1d", limits: limits), .tooManyNodes(limit: 2))
    }
}
