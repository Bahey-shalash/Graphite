import XCTest
@testable import MermaidDiagrams

/// The inputs of Mermaid 12.1.0's user journey parser spec (`journey.spec.js`, as Pele ports it in `tests/compat`),
/// the user journey inputs of Pele's own rendering tests, the documentation's example, and the errors.
final class UserJourneyParserTests: XCTestCase {
    private func userJourney(_ source: String) throws -> UserJourneyDiagram {
        try UserJourneyReading.userJourney(source)
    }

    private func readError(_ source: String) -> MermaidDiagramReadError? {
        UserJourneyReading.readError(source)
    }

    // MARK: Mermaid's parser spec

    func testATitleIsRead() throws {
        XCTAssertEqual(try userJourney("journey\ntitle Adding journey diagram functionality to mermaid").title,
                       "Adding journey diagram functionality to mermaid")
    }

    func testAnAccessibilityDescriptionOnOneLineIsRead() throws {
        let diagram = try userJourney("""
        journey
        accDescr: A user journey for family shopping
        title Adding journey diagram functionality to mermaid
        section Order from website
        """)
        XCTAssertEqual(diagram.accessibilityDescription, "A user journey for family shopping")
        XCTAssertEqual(diagram.sections.map(\.spokenText), ["Order from website"])
    }

    func testAnAccessibilityDescriptionOverSeveralLinesIsReadAndATitleMayFollowItsBrace() throws {
        let diagram = try userJourney("journey\naccDescr {\n        A user journey for\n        family shopping\n      }"
                                      + "title Adding journey diagram functionality to mermaid\n"
                                      + "accTitle: Adding acc journey diagram functionality to mermaid\nsection Order from website")
        XCTAssertEqual(diagram.accessibilityDescription, "A user journey for family shopping", "Its lines are joined as a screen reader reads them")
        XCTAssertEqual(diagram.title, "Adding journey diagram functionality to mermaid")
        XCTAssertEqual(diagram.accessibilityTitle, "Adding acc journey diagram functionality to mermaid")
    }

    func testAnAccessibilityTitleAloneLeavesNoDescription() throws {
        let diagram = try userJourney("journey\n    accTitle: The title\n    section Order from website")
        XCTAssertEqual(diagram.accessibilityTitle, "The title")
        XCTAssertNil(diagram.accessibilityDescription)
    }

    func testASectionsTextBreaksAtBreakTags() throws {
        let diagram = try userJourney("journey\ntitle Adding gantt diagram functionality to mermaid\nsection Line1<br>Line2<br/>Line3</br />Line4<br\t/>Line5")
        XCTAssertEqual(diagram.sections.first?.lines.prefix(2), ["Line1", "Line2"])
    }

    func testTasksKeepTheirScoreActorsAndSection() throws {
        let diagram = try userJourney("""
        journey
        title Adding journey diagram functionality to mermaid
        section Documentation
        A task: 5: Alice, Bob, Charlie
        B task: 3:Bob, Charlie
        C task: 5
        D task: 5: Charlie, Alice
        E task: 5:
        section Another section
        P task: 5:
        Q task: 5:
        R task: 5:
        """)
        XCTAssertEqual(diagram.tasks.map(\.label.spokenText), ["A task", "B task", "C task", "D task", "E task", "P task", "Q task", "R task"])
        XCTAssertEqual(diagram.tasks.map(\.score), [5, 3, 5, 5, 5, 5, 5, 5])
        XCTAssertEqual(diagram.tasks.map(\.actors), [["Alice", "Bob", "Charlie"], ["Bob", "Charlie"], [], ["Charlie", "Alice"], [""], [""], [""], [""]])
        XCTAssertEqual(diagram.tasks.map(\.sectionIndex), [0, 0, 0, 0, 0, 1, 1, 1])
        XCTAssertEqual(diagram.sections.map(\.spokenText), ["Documentation", "Another section"])
    }

    // MARK: Pele's rendering tests

    func testScoresAreReadAsJavaScriptNumbersAndNotANumberIsNone() throws {
        let diagram = try userJourney("journey\n  top: 5\n  mid: 3\n  low: 1\n  big: 100\n  neg: -7\n  zero: 0\n  word: abc\n  blank: \n  half: 3.5\n  inf: Infinity\n")
        XCTAssertEqual(diagram.tasks.map(\.score), [5, 3, 1, 100, -7, 0, nil, 0, 3.5, .infinity])
        XCTAssertEqual(diagram.tasks.map(\.level), [5, 3, 1, 5, 1, 1, 3, 1, 3.5, 5])
        XCTAssertEqual(diagram.tasks.map(\.mood), [.happy, .neutral, .sad, .happy, .sad, .sad, .neutral, .sad, .happy, .happy])
    }

    func testANamelessActorIsKeptOnItsTaskAndLeftOutOfTheActors() throws {
        let diagram = try userJourney("journey\n  a: 5:\n  b: 3: , Real,\n")
        XCTAssertEqual(diagram.tasks.map(\.actors), [[""], ["", "Real", ""]])
        XCTAssertEqual(diagram.actorNames, ["Real"])
    }

    func testATaskBelongsToTheSectionWrittenLastAndSectionsWithoutTasksAreKept() throws {
        let diagram = try userJourney("journey\n  first: 3\n  section A\n  section B\n    b1: 3\n    b2: 3\n  section C\n    c1: 3\n  section D\n")
        XCTAssertEqual(diagram.sections.map(\.spokenText), ["A", "B", "C", "D"])
        XCTAssertEqual(diagram.tasks.map(\.sectionIndex), [nil, 1, 1, 2])
    }

    func testTagsAndIconNamesStayAsWritten() throws {
        let diagram = try userJourney("journey\n  title fa:fa-check <u>T</u>\n  <b>bold</b> a<T>: 3: <i>Me</i>\n")
        XCTAssertEqual(diagram.title, "fa:fa-check <u>T</u>")
        XCTAssertEqual(diagram.tasks.first?.label.lines, ["<b>bold</b> a<T>"])
        XCTAssertEqual(diagram.tasks.first?.actors, ["<i>Me</i>"])
    }

    func testAccessibleNamesAreRead() throws {
        let diagram = try userJourney("journey\n  accTitle: Short name\n  accDescr {\n    A longer\n    description\n  }\n  a: 3\n")
        XCTAssertEqual(diagram.accessibilityTitle, "Short name")
        XCTAssertEqual(diagram.accessibilityDescription, "A longer description")
        XCTAssertEqual(diagram.tasks.count, 1)
    }

    func testAnEmptyJourneyALoneTitleAndSectionsWithoutTasksRead() throws {
        XCTAssertEqual(try userJourney("journey"), UserJourneyDiagram())
        XCTAssertEqual(try userJourney("journey\n  title Only").title, "Only")
        XCTAssertEqual(try userJourney("journey\n  section S\n  section T").sections.count, 2)
    }

    func testTheModelHoldsWhatTheTextSays() throws {
        let diagram = try userJourney("journey\n  title T\n  First: 2\n  section S\n    A task: 5: Bob, Alice\n    B task: x:\n")
        XCTAssertEqual(diagram.title, "T")
        XCTAssertEqual(diagram.tasks, [
            UserJourneyTask(label: DiagramLabel("First"), score: 2, actors: [], sectionIndex: nil),
            UserJourneyTask(label: DiagramLabel("A task"), score: 5, actors: ["Bob", "Alice"], sectionIndex: 0),
            UserJourneyTask(label: DiagramLabel("B task"), score: nil, actors: [""], sectionIndex: 0),
        ])
    }

    // MARK: Statements

    func testKeywordsAreReadWithoutRegardToCaseAndOnlyBeforeASpace() throws {
        let diagram = try userJourney("journey\n  TITLE Upper\n  Section One\n  titles: 3\n  title: 4")
        XCTAssertEqual(diagram.title, "Upper")
        XCTAssertEqual(diagram.sections.map(\.spokenText), ["One"])
        XCTAssertEqual(diagram.tasks.map(\.label.spokenText), ["titles", "title"])
    }

    func testATitleAloneOnItsLineTakesTheNextLine() throws {
        let diagram = try userJourney("journey\n  title\n  My day\n  a: 3")
        XCTAssertEqual(diagram.title, "My day")
        XCTAssertEqual(diagram.tasks.count, 1)
    }

    func testCommentsAreSkippedAndANumberSignEndsATasksData() throws {
        let diagram = try userJourney("journey\n  %% a comment\n  # another\n  t: 5: Me # who\n  u: 4 %% not a comment here")
        XCTAssertEqual(diagram.tasks.map(\.actors), [["Me"], []])
        XCTAssertEqual(diagram.tasks.map(\.score), [5, nil], "A comment does not end a task's data, as in Mermaid")
    }

    func testTextAfterAThirdColonIsLeft() throws {
        XCTAssertEqual(try userJourney("journey\n  a: 5: x: y").tasks.first?.actors, ["x"])
    }

    func testABreakTagEndsALineAndASemicolonEndsTheTextSoNoEntityCodeFitsInIt() throws {
        XCTAssertEqual(try userJourney("journey\n  Tea and cake<br>at four : 5").tasks.first?.label.lines, ["Tea and cake", "at four"])
        XCTAssertEqual(readError("journey\n  Tea &amp; cake: 5"), .invalidSyntax(line: 2, problem: .expectedTaskScore))
    }

    // MARK: Errors and limits

    func testWhatMermaidRejectsIsAnError() {
        XCTAssertEqual(readError("journey\n  A task\n"), .invalidSyntax(line: 2, problem: .expectedTaskScore))
        XCTAssertEqual(readError("journey\n  A task:\n"), .invalidSyntax(line: 2, problem: .expectedTaskScore))
        XCTAssertEqual(readError("journey\n  A; B: 3\n"), .invalidSyntax(line: 2, problem: .expectedTaskScore))
        XCTAssertEqual(readError("journey\n  : 5\n"), .invalidSyntax(line: 2, problem: .unexpectedText(": 5")))
        XCTAssertEqual(readError("journey\n  a: 5; b"), .invalidSyntax(line: 2, problem: .unexpectedText("; b")))
        XCTAssertEqual(readError("journey\n  accDescr {\n  never closed\n"), .invalidSyntax(line: 2, problem: .unclosedAccessibilityDescription))
    }

    func testTheKeywordAgainIsUnexpectedEvenAtTheStartOfATask() {
        XCTAssertEqual(readError("journey\n  a: 3\n  journey"), .invalidSyntax(line: 3, problem: .unexpectedText("journey")))
        XCTAssertEqual(readError("journey\n  Journey home: 3"), .invalidSyntax(line: 2, problem: .unexpectedText("Journey home: 3")))
        XCTAssertNil(readError("journey\n  journeys: 3"))
    }

    func testSectionsAndTasksPastTheNodeLimitAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        XCTAssertNil(UserJourneyReading.readError("journey\n  section S\n  a: 1\n  b: 2", limits: limits))
        XCTAssertEqual(UserJourneyReading.readError("journey\n  section S\n  a: 1\n  b: 2\n  c: 3", limits: limits), .tooManyNodes(limit: 3))
    }

    func testActorsNamedPastTheEdgeLimitAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumEdgeCount = 3
        XCTAssertNil(UserJourneyReading.readError("journey\n  a: 1: x, y\n  b: 2: x", limits: limits))
        XCTAssertEqual(UserJourneyReading.readError("journey\n  a: 1: x, y\n  b: 2: x,", limits: limits), .tooManyEdges(limit: 3))
    }

    // MARK: Mermaid's documentation

    func testTheDocumentationsExampleReads() throws {
        let diagram = try userJourney("""
        journey
            title My working day
            section Go to work
              Make tea: 5: Me
              Go upstairs: 3: Me
              Do work: 1: Me, Cat
            section Go home
              Go downstairs: 5: Me
              Sit down: 5: Me
        """)
        XCTAssertEqual(diagram.title, "My working day")
        XCTAssertEqual(diagram.sections.map(\.spokenText), ["Go to work", "Go home"])
        XCTAssertEqual(diagram.tasks.map(\.score), [5, 3, 1, 5, 5])
        XCTAssertEqual(diagram.tasks.map(\.sectionIndex), [0, 0, 0, 1, 1])
        XCTAssertEqual(diagram.actorNames, ["Cat", "Me"])
    }
}
