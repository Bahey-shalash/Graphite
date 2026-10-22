import XCTest
@testable import MermaidDiagrams

/// Notes, on the examples of Mermaid's documentation and its parser specs.
final class StateDiagramNoteSyntaxTests: XCTestCase {
    private func read(_ source: String) throws -> StateDiagram {
        try StateDiagramReading.stateDiagram(source)
    }

    func testTheDocumentationsNotesSitOnTheirSides() throws {
        let diagram = try read("""
            stateDiagram-v2
                State1: The state with a note
                note right of State1
                    Important information! You can write
                    notes.
                end note
                State1 --> State2
                note left of State2 : This is the note to the left.
        """)
        XCTAssertEqual(diagram.notes.map(\.side), [.right, .left])
        XCTAssertEqual(diagram.notes.map { note in diagram.states[note.stateIndex].identifier }, ["State1", "State2"])
        XCTAssertEqual(diagram.notes[0].text.lines, ["Important information! You can write", "notes."])
        XCTAssertEqual(diagram.notes[1].text.lines, ["This is the note to the left."])
    }

    func testEndNoteEndsANoteOnlyAtTheStartOfALine() throws {
        let diagram = try read("""
        stateDiagram-v2
          State1
          note right of State1
            this sentence contains end note as part of the note text
          end note
          State1 --> State2
        """)
        XCTAssertEqual(diagram.notes[0].text.lines, ["this sentence contains end note as part of the note text"])
        XCTAssertEqual(diagram.transitionIdentifiers, [["State1", "State2"]])
    }

    func testEverySpellingOfALineBreakEndsALineOfANote() throws {
        let diagram = try read("stateDiagram\n  State1\n  note right of State1\n    Line1<br>Line2<br/>Line3<br />Line4\n  end note")
        XCTAssertEqual(diagram.notes[0].text.lines, ["Line1", "Line2", "Line3", "Line4"])
        XCTAssertEqual(try read("stateDiagram\n  note left of Active : this is a short<br/>note").notes[0].text.lines, ["this is a short", "note"])
    }

    func testANoteNamesItsStateWhenNothingElseHas() throws {
        let diagram = try read("stateDiagram-v2\n  note left of Lonely : alone\n  note right of [*] : where it starts")
        XCTAssertEqual(diagram.identifiers, ["Lonely", "[*]"])
        XCTAssertEqual(diagram.states[1].kind, .start)
    }

    func testAStateMayHaveSeveralNotes() throws {
        let diagram = try read("stateDiagram-v2\n  A\n  note right of A : one\n  note right of A : two\n  NOTE LEFT OF A : three")
        XCTAssertEqual(diagram.notes.map(\.text.lines), [["one"], ["two"], ["three"]])
        XCTAssertEqual(Set(diagram.notes.map(\.stateIndex)), [0])
    }

    func testAFloatingNoteIsReadAndNotDrawn() throws {
        let diagram = try read("stateDiagram-v2\n  foo: bar\n  note \"This is a floating note\" as N1")
        XCTAssertEqual(diagram.identifiers, ["foo"])
        XCTAssertTrue(diagram.notes.isEmpty)
    }

    func testABrokenNoteIsReported() {
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nA\nnote right of A\nnever ended\n")?.line, 3)
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nA\nnote right of A\nnever ended\n")?.problem, .unclosedNote)
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nnote over A : text")?.problem, .unexpectedText("over A : text"))
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nnote left of : text")?.problem, .expectedState)
        XCTAssertEqual(StateDiagramReading.syntaxProblem("stateDiagram-v2\nnote \"floating\" N1")?.problem, .unexpectedText("N1"))
    }
}
