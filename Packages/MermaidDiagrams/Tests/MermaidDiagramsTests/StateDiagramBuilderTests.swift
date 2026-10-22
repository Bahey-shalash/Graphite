import XCTest
@testable import MermaidDiagrams

/// How states, starts and ends, and composite bodies are collected, on Mermaid's composite and concurrency examples.
final class StateDiagramBuilderTests: XCTestCase {
    private func read(_ source: String) throws -> StateDiagram {
        try StateDiagramReading.stateDiagram(source)
    }

    func testEachCompositeBodyHasItsOwnStartAndEnd() throws {
        let diagram = try read("""
        stateDiagram-v2
            [*] --> First
            state First {
                [*] --> second
                second --> [*]
            }
            First --> [*]
        """)
        XCTAssertEqual(diagram.identifiers, ["[*]", "First", "[*]", "second", "[*]", "[*]"])
        XCTAssertEqual(diagram.states.map(\.kind), [.start, .state, .start, .state, .end, .end])
        XCTAssertEqual(diagram.states.map(\.compositeIndex), [nil, nil, 0, 0, 0, nil])
        XCTAssertEqual(diagram.composites, [StateDiagramComposite(stateIndex: 1, parentCompositeIndex: nil)])
    }

    func testCompositesNestAndKeepTheirDirection() throws {
        let diagram = try read("""
        stateDiagram
            direction LR
            [*] --> A
            state B {
              direction TB
              a --> b
              state C {
                c
              }
            }
            B --> D
        """)
        XCTAssertEqual(diagram.direction, .leftToRight)
        XCTAssertEqual(diagram.composites.map(\.parentCompositeIndex), [nil, 0])
        XCTAssertEqual(diagram.composites.map(\.direction), [.topToBottom, nil])
        XCTAssertEqual(diagram.state("c")?.compositeIndex, 1)
        XCTAssertEqual(diagram.state("C")?.compositeIndex, 0)
        XCTAssertNil(diagram.state("D")?.compositeIndex)
    }

    func testDividersMakeConcurrentRegionsEachWithItsOwnStart() throws {
        let diagram = try read("""
        stateDiagram-v2
            [*] --> Active
            state Active {
                [*] --> NumLockOff
                NumLockOff --> NumLockOn : EvNumLockPressed
                --
                [*] --> CapsLockOff
                --
                [*] --> ScrollLockOff
            }
        """)
        XCTAssertEqual(diagram.composites.first?.regionCount, 3)
        XCTAssertEqual(diagram.states.filter { state in state.kind == .start }.count, 4)
    }

    func testACompositeWrittenTwiceIsOneComposite() throws {
        let diagram = try read("stateDiagram-v2\n  state A {\n    a\n  }\n  state A {\n    b\n  }")
        XCTAssertEqual(diagram.composites.count, 1)
        XCTAssertEqual(diagram.state("b")?.compositeIndex, 0)
    }

    func testACompositeNamedInsideItselfIsNotItsOwnMember() throws {
        let diagram = try read("stateDiagram-v2\n  state A {\n    A --> a\n  }")
        XCTAssertNil(diagram.state("A")?.compositeIndex)
        XCTAssertEqual(diagram.state("a")?.compositeIndex, 0)
    }

    func testABodyLeftOpenOrClosedTwiceIsReported() {
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nstate Moving {\n  slow --> fast\n")?.problem,
                       .unclosedCompositeState(identifier: "Moving"))
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nstate A {\n}\n}")?.line, 4)
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nstate A {\n}\n}")?.problem, .closingBraceWithoutCompositeState)
    }
}
