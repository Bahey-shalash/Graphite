import XCTest
@testable import MermaidDiagrams

/// The inputs of Mermaid 12.1.0's timeline parser spec (`timeline.spec.js`, as Pele ports it in `tests/compat`), the
/// examples of Mermaid's timeline documentation, and the errors.
final class TimelineParserTests: XCTestCase {
    private func timeline(_ source: String) throws -> TimelineDiagram {
        try TimelineReading.timeline(source)
    }

    private func texts(_ labels: [DiagramLabel]) -> [String] {
        labels.map(\.spokenText)
    }

    // MARK: Direction and sections

    func testTheDirectionIsLeftToRightUnlessTheKeywordsLineSaysTD() throws {
        XCTAssertEqual(try timeline("timeline\n    section abc-123").direction, .leftToRight)
        XCTAssertEqual(try timeline("timeline TD\n    section abc-123").direction, .topToBottom)
        XCTAssertEqual(try timeline("timeline LR\n    section abc-123").direction, .leftToRight)
        XCTAssertEqual(try timeline("timeline td\n  a").direction, .topToBottom)
    }

    func testOtherTextOnTheKeywordsLineIsAPeriod() throws {
        let diagram = try timeline("timeline TDX\n  a")
        XCTAssertEqual(diagram.direction, .leftToRight)
        XCTAssertEqual(texts(diagram.periods.map(\.label)), ["TDX", "a"])
    }

    func testASectionHoldsThePeriodsWrittenAfterIt() throws {
        let diagram = try timeline("timeline\n    section abc-123\n    task1\n    task2\n    section abc-456\n    task3\n    task4")
        XCTAssertEqual(texts(diagram.sections), ["abc-123", "abc-456"])
        XCTAssertEqual(texts(diagram.periods.map(\.label)), ["task1", "task2", "task3", "task4"])
        XCTAssertEqual(diagram.periods.map(\.sectionIndex), [0, 0, 1, 1])
    }

    func testPeriodsBeforeTheFirstSectionHaveNone() throws {
        let diagram = try timeline("timeline\n  2001\n  section Later\n  2002")
        XCTAssertEqual(diagram.periods.map(\.sectionIndex), [nil, 0])
    }

    // MARK: Periods and events

    func testEventsFollowTheirPeriodOnItsLineAndOnTheLinesAfter() throws {
        let diagram = try timeline("timeline\n    section abc-123\n      task1: event1\n      task2: event2: event3\n           : event4: event5\n   ")
        XCTAssertEqual(diagram.periods.map { period in texts(period.events) }, [["event1"], ["event2", "event3", "event4", "event5"]])
    }

    func testAnEventKeepsAMarkdownLinkAsText() throws {
        let diagram = try timeline("timeline\n    section abc-123\n      task1: [event1](http://example.com)\n      task2: event2: event3\n   ")
        XCTAssertEqual(texts(diagram.periods[0].events), ["[event1](http://example.com)"])
    }

    func testSemicolonsAreText() throws {
        let diagram = try timeline("timeline\n      title ;my;title;\n      section ;a;bc-123;\n      ;ta;sk1;: ;ev;ent1; : ;ev;ent2; : ;ev;ent3;\n   ")
        XCTAssertEqual(diagram.title, ";my;title;")
        XCTAssertEqual(texts(diagram.sections), [";a;bc-123;"])
        XCTAssertEqual(texts(diagram.periods.map(\.label)), [";ta;sk1;"])
        XCTAssertEqual(texts(diagram.periods[0].events), [";ev;ent1;", ";ev;ent2;", ";ev;ent3;"])
    }

    func testNumberSignsAreTextInATitleASectionAndEvents() throws {
        let diagram = try timeline("timeline\n      title #my#title#\n      section #a#bc-123#\n      task1: #ev#ent1# : #ev#ent2# : #ev#ent3#\n   ")
        XCTAssertEqual(diagram.title, "#my#title#")
        XCTAssertEqual(texts(diagram.sections), ["#a#bc-123#"])
        XCTAssertEqual(texts(diagram.periods.map(\.label)), ["task1"])
        XCTAssertEqual(texts(diagram.periods[0].events), ["#ev#ent1#", "#ev#ent2#", "#ev#ent3#"])
    }

    func testAPeriodEndsAtANumberSignWhichStartsAComment() throws {
        let diagram = try timeline("timeline\n  task #1 : not an event\n  # a comment line\n  %% another\n  2002 : event")
        XCTAssertEqual(texts(diagram.periods.map(\.label)), ["task", "2002"])
        XCTAssertEqual(texts(diagram.periods[1].events), ["event"])
    }

    func testABreakTagEndsALineAndOtherTagsStayAsWritten() throws {
        let diagram = try timeline("timeline\n  Industry 1.0 : Machinery, Water power, Steam <br>power\n  2000 : <b>bold</b> &amp; more")
        XCTAssertEqual(diagram.periods[0].events[0].lines, ["Machinery, Water power, Steam", "power"])
        XCTAssertEqual(diagram.periods[1].events[0].lines, ["<b>bold</b> & more"])
    }

    func testKeywordsAreReadWithoutRegardToCase() throws {
        let diagram = try timeline("timeline\n  TITLE Upper\n  Section One\n  a")
        XCTAssertEqual(diagram.title, "Upper")
        XCTAssertEqual(texts(diagram.sections), ["One"])
        XCTAssertEqual(texts(try timeline("timeline\n  sections 2023\n  title").periods.map(\.label)), ["sections 2023", "title"])
    }

    func testAccessibilityTextIsRead() throws {
        let diagram = try timeline("timeline\n  accTitle: History\n  accDescr {\n    Platforms\n    by year\n  }\n  2002 : LinkedIn")
        XCTAssertEqual(diagram.accessibilityTitle, "History")
        XCTAssertEqual(diagram.accessibilityDescription, "Platforms by year")
        XCTAssertEqual(diagram.periods.count, 1)
    }

    // MARK: Errors and limits

    func testAnEventBeforeAnyPeriodIsAnError() {
        XCTAssertEqual(TimelineReading.readError("timeline\n  title T\n  : lonely"), .invalidSyntax(line: 3, problem: .eventWithoutPeriod))
    }

    func testAColonWithoutASpaceAfterItIsUnexpected() {
        XCTAssertEqual(TimelineReading.readError("timeline\n  10:30 : Meeting"), .invalidSyntax(line: 2, problem: .unexpectedText(":30 : Meeting")))
    }

    func testTheKeywordAgainIsUnexpected() {
        XCTAssertEqual(TimelineReading.readError("timeline\n  2002\n  timeline"), .invalidSyntax(line: 3, problem: .unexpectedText("timeline")))
    }

    func testAnEmptyTimelineReads() throws {
        let diagram = try timeline("timeline")
        XCTAssertTrue(diagram.periods.isEmpty)
        XCTAssertNil(diagram.title)
    }

    func testSectionsPeriodsAndEventsPastTheLimitAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        XCTAssertNil(TimelineReading.readError("timeline\n  section S\n  2002 : one", limits: limits))
        XCTAssertEqual(TimelineReading.readError("timeline\n  section S\n  2002 : one : two", limits: limits), .tooManyNodes(limit: 3))
    }

    // MARK: Mermaid's documentation

    func testTheDocumentationsExamplesRead() throws {
        let following = try timeline("timeline\n    title History of Social Media Platform\n    2002 : LinkedIn\n    2004 : Facebook\n         : Google\n    2005 : YouTube\n    2006 : Twitter")
        XCTAssertEqual(following.title, "History of Social Media Platform")
        XCTAssertEqual(following.periods.map { period in texts([period.label] + period.events) },
                       [["2002", "LinkedIn"], ["2004", "Facebook", "Google"], ["2005", "YouTube"], ["2006", "Twitter"]])
        let sectioned = try timeline("""
        timeline
                title MermaidChart 2023 Timeline
                section 2023 Q1 <br> Release Personal Tier
                  Bullet 1 : sub-point 1a : sub-point 1b
                       : sub-point 1c
                  Bullet 2 : sub-point 2a : sub-point 2b
                section 2023 Q2 <br> Release XYZ Tier
                  Bullet 3 : sub-point <br> 3a : sub-point 3b
                       : sub-point 3c
                  Bullet 4 : sub-point 4a : sub-point 4b
        """)
        XCTAssertEqual(sectioned.sections.map(\.lines), [["2023 Q1", "Release Personal Tier"], ["2023 Q2", "Release XYZ Tier"]])
        XCTAssertEqual(sectioned.periods.map(\.events.count), [3, 2, 3, 2])
        XCTAssertEqual(sectioned.periods[2].events[0].lines, ["sub-point", "3a"])
    }
}
