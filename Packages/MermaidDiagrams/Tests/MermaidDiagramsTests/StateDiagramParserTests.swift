import XCTest
@testable import MermaidDiagrams

/// The statements of a state diagram, on the examples of Mermaid's documentation and its parser specs (Pele's
/// `tests/compat/state`).
final class StateDiagramParserTests: XCTestCase {
    private func read(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> StateDiagram {
        try StateDiagramReading.stateDiagram(source, limits: limits)
    }

    func testBothKeywordsReadAStateDiagram() throws {
        for keyword in ["stateDiagram", "stateDiagram-v2"] {
            XCTAssertEqual(try read("\(keyword)\n  [*] --> Still\n  Still --> [*]").transitions.count, 2, keyword)
        }
    }

    func testTheDocumentationsFirstExampleHasOneStartAndOneEnd() throws {
        let diagram = try read("""
        stateDiagram-v2
            [*] --> Still
            Still --> [*]

            Still --> Moving
            Moving --> Still
            Moving --> Crash
            Crash --> [*]
        """)
        XCTAssertEqual(diagram.identifiers, ["[*]", "Still", "[*]", "Moving", "Crash"])
        XCTAssertEqual(diagram.states.map(\.kind), [.start, .state, .end, .state, .state])
        XCTAssertEqual(diagram.transitionIdentifiers, [["[*]", "Still"], ["Still", "[*]"], ["Still", "Moving"], ["Moving", "Still"],
                                                       ["Moving", "Crash"], ["Crash", "[*]"]])
        XCTAssertEqual(diagram.transitions[5].targetIndex, 2, "Every end of the top level is one state")
        XCTAssertEqual(diagram.direction, .topToBottom)
    }

    func testAStateNamedAloneIsAStateNamedByItsIdentifier() throws {
        let diagram = try read("stateDiagram-v2\n    stateId\n")
        XCTAssertEqual(diagram.identifiers, ["stateId"])
        XCTAssertEqual(diagram.states[0].name.lines, ["stateId"])
    }

    func testATextAfterAColonDescribesTheState() throws {
        for source in ["stateDiagram-v2\n  namedState1 : Small State 1", "stateDiagram-v2\n  namedState1:Small State 1"] {
            XCTAssertEqual(try read(source).state("namedState1")?.descriptions, [DiagramLabel("Small State 1")], source)
        }
        XCTAssertEqual(try read("stateDiagram-v2\n  myState : status: active").state("myState")?.name.lines, ["status: active"])
    }

    func testEachTextWrittenForAStateIsKeptInOrder() throws {
        let diagram = try read("stateDiagram-v2\n  State1 : this is a string\n  State1 : this is another string\n  [*] --> State1")
        XCTAssertEqual(diagram.state("State1")?.descriptions.map(\.lines), [["this is a string"], ["this is another string"]])
    }

    func testATransitionsTextFollowsItsColonAndMayHoldColons() throws {
        let diagram = try read("""
        stateDiagram-v2
          s1 --> s2: A transition
          locked --> pending : recoverable error (ex: timeout)
          A --> B : info: key: value
          [*] --> State1 : This is the description +-!
          C --> D
        """)
        XCTAssertEqual(diagram.transitions.map { transition in transition.label?.lines },
                       [["A transition"], ["recoverable error (ex: timeout)"], ["info: key: value"], ["This is the description +-!"], nil])
    }

    func testTransitionsNeedNoSpaces() throws {
        XCTAssertEqual(try read("stateDiagram\n[*]-->Still\nStill-->[*]").transitionIdentifiers, [["[*]", "Still"], ["Still", "[*]"]])
    }

    func testABreakInATextEndsALine() throws {
        let diagram = try read("stateDiagram-v2\n  A --> B : should point to \\nB\n  C : one<br/>two")
        XCTAssertEqual(diagram.transitions[0].label?.lines, ["should point to", "B"])
        XCTAssertEqual(diagram.state("C")?.name.lines, ["one", "two"])
    }

    func testEmphasisMarkersAreTakenOffAText() throws {
        XCTAssertEqual(try read("stateDiagram-v2\n  A : a **bold** step_name").state("A")?.name.lines, ["a bold step_name"])
    }

    func testStatementsMayFollowEachOtherOnOneLine() throws {
        let diagram = try read("stateDiagram-v2\n\nclassDef exampleStyleClass background:#bbb;\na --> b class a exampleStyleClass")
        XCTAssertEqual(diagram.transitionIdentifiers, [["a", "b"]])
        XCTAssertEqual(diagram.unappliedStatementCount, 2)
    }

    func testStyleStatementsAreCountedAndNotApplied() throws {
        let diagram = try read("""
        stateDiagram
           classDef notMoving fill:white
           [*] --> Still:::notMoving
           Crash:::badBadEvent --> [*]
           [*]:::exampleStyleClass --> b
           class Moving, Crash movement
           style Still fill:#bbb
           click Still "https://example.com" "Go"
        """)
        XCTAssertEqual(diagram.unappliedStatementCount, 7)
        XCTAssertEqual(diagram.identifiers, ["[*]", "Still", "Crash", "[*]", "b"])
    }

    func testCommentsAreSkippedWhereverTheyStart() throws {
        let diagram = try read("""
        stateDiagram-v2
        %%initial_comment
        [*] --> Moving %%inline_comment
        Moving --> Still%% attached to a state
        # a line comment
        %% comment between
        Moving --> Crash
        """)
        XCTAssertEqual(diagram.identifiers, ["[*]", "Moving", "Still", "Crash"])
    }

    func testOnePercentSignIsText() throws {
        let diagram = try read("stateDiagram-v2\n% not a comment\nMoving --> Still %inline")
        XCTAssertEqual(diagram.identifiers, ["%", "not", "a", "comment", "Moving", "Still", "%inline"])
    }

    func testDirectionSetsTheWayTheDiagramRuns() throws {
        XCTAssertEqual(try read("stateDiagram\n  direction LR\n  [*] --> Still").direction, .leftToRight)
        XCTAssertEqual(try read("stateDiagram\n  direction bt\n  [*] --> Still").direction, .bottomToTop)
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram\n  direction XY\n")?.problem, .unknownDirection("XY"))
    }

    func testAccessibilityTextIsReadOnOneLineOrInBraces() throws {
        let titled = try read("stateDiagram-v2\n  accTitle: a simple title of the diagram\n  accDescr: a simple description\n  A")
        XCTAssertEqual(titled.accessibilityTitle, "a simple title of the diagram")
        XCTAssertEqual(titled.accessibilityDescription, "a simple description")
        let described = try read("stateDiagram\n  accDescr {\n     a simple description of the diagram\n    using multiple lines\n  }\n  A")
        XCTAssertEqual(described.accessibilityDescription, "a simple description of the diagram\nusing multiple lines")
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram\naccDescr {\nnever closed")?.problem, .unclosedAccessibilityDescription)
    }

    func testFrontMatterGivesTheTitle() throws {
        XCTAssertEqual(try read("---\ntitle: Simple sample\n---\nstateDiagram-v2\n    [*] --> Still").title, "Simple sample")
    }

    func testScaleAndHideEmptyDescriptionChangeNothing() throws {
        let diagram = try read("stateDiagram-v2\n  scale 350 width\n  hide empty description\n  [*] --> State1")
        XCTAssertEqual(diagram.identifiers, ["[*]", "State1"])
        XCTAssertEqual(diagram.unappliedStatementCount, 0)
    }

    func testAKeywordFollowedByAnythingButASpaceNamesAState() throws {
        let diagram = try read("stateDiagram-v2\n  classes --> notes\n  stateful --> hide\n  direction")
        XCTAssertEqual(diagram.identifiers, ["classes", "notes", "stateful", "hide", "direction"])
    }

    func testPropertyNamesOfJavaScriptAreOrdinaryStates() throws {
        let diagram = try read("stateDiagram-v2\n[*] --> __proto__\n__proto__ --> constructor")
        XCTAssertEqual(diagram.identifiers, ["[*]", "__proto__", "constructor"])
    }

    func testABrokenStatementIsReportedOnItsLine() {
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\n  A -->\n")?.line, 2)
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\n  A -->\n")?.problem, .expectedState)
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\n  A\n  A -> B")?.problem, .unexpectedText("-> B"))
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\n  \"quoted\" --> B")?.problem, .unexpectedText("\"quoted\" --> B"))
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\n  --\n")?.problem, .unexpectedText("--"))
    }

    func testStatesNotesAndTransitionsPastTheirLimitsAreRefused() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        XCTAssertEqual(FlowchartReading.readError("stateDiagram-v2\nA --> B\nC --> D", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertEqual(FlowchartReading.readError("stateDiagram-v2\nA --> B\nnote left of A : one\nnote left of B : two", limits: limits),
                       .tooManyNodes(limit: 3))
        limits = .standard
        limits.maximumEdgeCount = 2
        XCTAssertEqual(FlowchartReading.readError("stateDiagram-v2\nA --> B\nB --> C\nC --> A", limits: limits), .tooManyEdges(limit: 2))
    }
}
