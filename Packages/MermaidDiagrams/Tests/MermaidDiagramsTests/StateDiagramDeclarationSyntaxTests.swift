import XCTest
@testable import MermaidDiagrams

/// `state …` statements, on the examples of Mermaid's documentation and its parser specs.
final class StateDiagramDeclarationSyntaxTests: XCTestCase {
    private func read(_ source: String) throws -> StateDiagram {
        try StateDiagramReading.stateDiagram(source)
    }

    func testAQuotedDescriptionNamesTheStateItIsGivenTo() throws {
        let diagram = try read("stateDiagram-v2\n    state \"This is a state description\" as s2\n")
        XCTAssertEqual(diagram.identifiers, ["s2"])
        XCTAssertEqual(diagram.states[0].name.lines, ["This is a state description"])
    }

    func testAsInAStateNameIsNotTheKeyword() throws {
        let diagram = try read("stateDiagram-v2\n  assemble\n  assemblies\n  state assemble\n  state assemblies\n  state \"as\" as as")
        XCTAssertEqual(diagram.identifiers, ["assemble", "assemblies", "as"])
        XCTAssertEqual(diagram.state("as")?.name.lines, ["as"])
    }

    func testAColonAfterTheIdentifierAddsASecondDescription() throws {
        let diagram = try read("stateDiagram-v2\n  state \"Accumulate Enough Data\nLong State Name\" as long1:Just a test")
        XCTAssertEqual(diagram.state("long1")?.descriptions.map(\.lines), [["Accumulate Enough Data", "Long State Name"], ["Just a test"]])
    }

    func testAStateAloneAfterTheKeywordDeclaresNothing() throws {
        let diagram = try read("stateDiagram-v2\n  state foo\n  state bar baz\n  A")
        XCTAssertEqual(diagram.identifiers, ["A"])
    }

    func testStereotypesMakeChoicesForksAndJoins() throws {
        let diagram = try read("""
        stateDiagram-v2
            state if_state <<choice>>
            state fork_state <<FORK>>
            state join_state [[join]]
            [*] --> fork_state
            fork_state --> join_state
            join_state --> if_state
        """)
        XCTAssertEqual(diagram.identifiers, ["if_state", "fork_state", "join_state", "[*]"])
        XCTAssertEqual(diagram.states.map(\.kind), [.choice, .fork, .join, .start])
    }

    func testAStateKeepsTheKindItWasFirstNamedWith() throws {
        let diagram = try read("stateDiagram-v2\n  A --> fork1\n  state fork1 <<fork>>\n  state choice1 <<choice>>\n  choice1 --> A")
        XCTAssertEqual(diagram.state("fork1")?.kind, .state)
        XCTAssertEqual(diagram.state("choice1")?.kind, .choice)
    }

    func testATextGivenToAChoiceDrawsItAsABox() throws {
        let diagram = try read("stateDiagram-v2\n  state if_state <<choice>>\n  if_state : Decide")
        XCTAssertEqual(diagram.state("if_state")?.kind, .state)
        XCTAssertEqual(diagram.state("if_state")?.name.lines, ["Decide"])
    }

    func testABraceOpensACompositeBody() throws {
        let diagram = try read("stateDiagram-v2\n  state valid { X }\n  state \"Big State 1\" as bigState1 {\n    inner\n  }")
        XCTAssertEqual(diagram.composites.map { composite in diagram.states[composite.stateIndex].identifier }, ["valid", "bigState1"])
        XCTAssertEqual(diagram.state("bigState1")?.name.lines, ["Big State 1"])
        XCTAssertEqual(diagram.state("X")?.compositeIndex, 0)
        XCTAssertEqual(diagram.state("inner")?.compositeIndex, 1)
    }

    func testACompositesNameIsOneWord() {
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\n        state invalid syntax { Y }")?.problem,
                       .stateNameNotOneWord("invalid syntax"))
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nstate invalid syntax with more than 2 words { Z }")?.problem,
                       .stateNameNotOneWord("invalid syntax with more than 2 words"))
    }

    func testABrokenDeclarationIsReported() {
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nstate \"never closed")?.problem, .unclosedQuotation)
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nstate \"text\" is s1")?.problem, .unexpectedText("is s1"))
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nstate \"text\" as \n")?.problem, .expectedState)
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nstate <<fork>>")?.problem, .expectedState)
    }
}
