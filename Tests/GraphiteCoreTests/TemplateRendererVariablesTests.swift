import XCTest
@testable import GraphiteCore

/// The variables a template can hold, each with the text it becomes for one fixed moment:
/// Thursday 24 September 2026, 14:30 in Zurich.
final class TemplateRendererVariablesTests: XCTestCase {
    private let zurich = TimeZone(identifier: "Europe/Zurich")!

    private var sampleMoment: Date {
        var components = DateComponents(year: 2026, month: 9, day: 24, hour: 14, minute: 30)
        components.timeZone = zurich
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    private func rendered(_ template: String) -> String {
        TemplateRenderer.render(template, title: "Signals", date: sampleMoment, dateFormat: "YYYY-MM-DD", timeFormat: "HH:mm", timeZone: zurich)
    }

    func testEachVariableBecomesItsValueWithTheDefaultFormats() {
        let expectations: [(template: String, expected: String)] = [
            ("{{title}}", "Signals"),
            ("{{date}}", "2026-09-24"),
            ("{{time}}", "14:30"),
            ("{{yesterday}}", "2026-09-23"),
            ("{{tomorrow}}", "2026-09-25"),
        ]
        for expectation in expectations {
            XCTAssertEqual(rendered(expectation.template), expectation.expected, expectation.template)
        }
    }

    func testAFormatAfterAColonReplacesTheDefaultFormat() {
        let expectations: [(template: String, expected: String)] = [
            ("{{date:dddd, MMMM Do}}", "Thursday, September 24th"),
            ("{{date:YYYY/MM/DD}}", "2026/09/24"),
            ("{{time:h:mm A}}", "2:30 PM"),
            ("{{tomorrow:dddd}}", "Friday"),
            ("{{yesterday:YYYY-MM-DD HH:mm}}", "2026-09-23 14:30"),
        ]
        for expectation in expectations {
            XCTAssertEqual(rendered(expectation.template), expectation.expected, expectation.template)
        }
    }

    func testVariableNamesMatchWhateverTheLetterCaseAndSpacing() {
        let expectations: [(template: String, expected: String)] = [
            ("{{TITLE}}", "Signals"),
            ("{{Date}}", "2026-09-24"),
            ("{{ TIME : h A }}", "2 PM"),
            ("{{ Tomorrow }}", "2026-09-25"),
            ("{{ date +1d : YYYY-MM-DD }}", "2026-09-25"),
        ]
        for expectation in expectations {
            XCTAssertEqual(rendered(expectation.template), expectation.expected, expectation.template)
        }
    }

    func testEachOffsetUnitMovesTheMomentByThatMuch() {
        let expectations: [(template: String, expected: String)] = [
            ("{{date+1y:YYYY-MM-DD}}", "2027-09-24"),
            ("{{date+1Q:YYYY-MM-DD}}", "2026-12-24"),
            ("{{date+1M:YYYY-MM-DD}}", "2026-10-24"),
            ("{{date+1w:YYYY-MM-DD}}", "2026-10-01"),
            ("{{date+1d:YYYY-MM-DD}}", "2026-09-25"),
            ("{{date+2h:HH:mm}}", "16:30"),
            ("{{date+45m:HH:mm}}", "15:15"),
            ("{{date+90s:HH:mm:ss}}", "14:31:30"),
            ("{{date-1d:YYYY-MM-DD}}", "2026-09-23"),
            ("{{date-2w:YYYY-MM-DD}}", "2026-09-10"),
            ("{{time+30m}}", "15:00"),
            ("{{date+1d}}", "2026-09-25"),
            ("{{yesterday+1d}}", "2026-09-24"),
            ("{{tomorrow-1w:YYYY-MM-DD}}", "2026-09-18"),
        ]
        for expectation in expectations {
            XCTAssertEqual(rendered(expectation.template), expectation.expected, expectation.template)
        }
    }

    func testAnOffsetThatCannotBeRepresentedLeavesTheVariableAsWritten() {
        let unrepresentable = [
            "{{date+\(Int.max)y}}", "{{date+\(Int.max)Q}}", "{{date+\(Int.max)M}}", "{{date+\(Int.max)w}}", "{{date+\(Int.max)d}}",
            "{{date+\(Int.max)h}}", "{{date+\(Int.max)m}}", "{{date+\(Int.max)s:YYYY}}", "{{date-\(Int.max)d}}",
            "{{date+99999999999999999999d}}", "{{date+10001y}}", "{{tomorrow+\(Int.max)d}}",
        ]
        for template in unrepresentable {
            XCTAssertEqual(rendered(template), template)
        }
        XCTAssertEqual(rendered("a {{date+10001y}} b {{title}}"), "a {{date+10001y}} b Signals", "Only the unrepresentable variable stays as written.")
    }

    func testTextThatIsNotAVariableIsKeptAsWritten() {
        let untouched = ["{{unknown}}", "{title}", "{{ }}", "{{date", "date}}", "{{date+d}}", "{{datetime}}"]
        for template in untouched {
            XCTAssertEqual(rendered(template), template)
        }
    }

    func testSeveralVariablesInOneTemplateAreFilledInPlaceKeepingTheTextBetween() {
        XCTAssertEqual(rendered("# {{title}}\nOn {{date:dddd}} at {{time}}: [[{{yesterday}}]] [[{{tomorrow}}]]\n"),
                       "# Signals\nOn Thursday at 14:30: [[2026-09-23]] [[2026-09-25]]\n")
    }

    func testTheTimeZoneDecidesWhichDayAMomentFallsOn() throws {
        let tokyo = try XCTUnwrap(TimeZone(identifier: "Asia/Tokyo"))
        let lateEvening = TemplateRenderer.render("{{date}} {{time}}", title: "", date: sampleMoment, dateFormat: "YYYY-MM-DD", timeFormat: "HH:mm", timeZone: tokyo)
        XCTAssertEqual(lateEvening, "2026-09-24 21:30")
    }
}
