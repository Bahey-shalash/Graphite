import XCTest
@testable import MermaidDiagrams

/// Notes beside their states.
final class StateDiagramSurroundingsTests: XCTestCase {
    private func layout(_ source: String) throws -> StateDiagramLayout {
        try StateDiagramUniformLayout.layout(source)
    }

    func testANoteSitsBesideItsStateAcrossTheFlowARankGapAway() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> B\nnote right of A : on the right\nnote left of B : on the left")
        let right = laidOut.notes[0]
        let left = laidOut.notes[1]
        XCTAssertEqual(right.frame.minX - laidOut.states[0].frame.maxX, 44, accuracy: 0.01)
        XCTAssertEqual(right.frame.midY, laidOut.states[0].frame.midY, accuracy: 0.01)
        XCTAssertEqual(laidOut.states[1].frame.minX - left.frame.maxX, 44, accuracy: 0.01)
        XCTAssertEqual(right.connector.start, CGPoint(x: laidOut.states[0].frame.maxX, y: laidOut.states[0].frame.midY))
        XCTAssertEqual(right.connector.allPoints.last, CGPoint(x: right.frame.minX, y: right.frame.midY))
    }

    func testANoteIsSizedAroundItsSmallerText() throws {
        let note = try XCTUnwrap(layout("stateDiagram-v2\nA\nnote right of A\nfirst line\nsecond\nend note").notes.first)
        XCTAssertEqual(note.text.lines, ["first line", "second"])
        XCTAssertEqual(note.text.fontSize, 14)
        XCTAssertEqual(note.frame.size, CGSize(width: 10 * 7 + 24, height: 2 * 21 + 16))
        XCTAssertEqual(note.text.center, CGPoint(x: note.frame.midX, y: note.frame.midY))
    }

    func testANoteWrapsAt320Points() throws {
        let note = try XCTUnwrap(layout("stateDiagram-v2\nA\nnote left of A : " + Array(repeating: "word", count: 30).joined(separator: " ")).notes.first)
        XCTAssertGreaterThan(note.text.lines.count, 1)
        XCTAssertLessThanOrEqual(note.text.size.width, 320)
    }

    func testInAFlowThatRunsAcrossNotesSitAboveAndBelow() throws {
        let laidOut = try layout("stateDiagram-v2\ndirection LR\nA --> B\nnote left of A : above\nnote right of A : below")
        let state = laidOut.states[0].frame
        XCTAssertEqual(state.minY - laidOut.notes[0].frame.maxY, 44, accuracy: 0.01)
        XCTAssertEqual(laidOut.notes[1].frame.minY - state.maxY, 44, accuracy: 0.01)
        XCTAssertEqual(laidOut.notes[0].frame.midX, state.midX, accuracy: 0.01)
    }

    func testNotesOnOneSideStackDownCenteredOnTheirState() throws {
        let laidOut = try layout("stateDiagram-v2\nA\nnote right of A : one\nnote right of A : two")
        let first = laidOut.notes[0].frame
        let second = laidOut.notes[1].frame
        XCTAssertEqual(second.minY - first.maxY, 40, accuracy: 0.01)
        XCTAssertEqual((first.minY + second.maxY) / 2, laidOut.states[0].frame.midY, accuracy: 0.01)
        XCTAssertNotEqual(laidOut.notes[0].connector.start, laidOut.notes[1].connector.start, "Their lines leave the box apart")
    }

    func testAStateWithANoteStaysInLineWithItsTransitions() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> B\nB --> C\nnote right of B : a note far wider than any of the states")
        XCTAssertEqual(laidOut.states[0].frame.midX, laidOut.states[1].frame.midX, accuracy: 0.01)
        XCTAssertEqual(laidOut.states[2].frame.midX, laidOut.states[1].frame.midX, accuracy: 0.01)
    }

    func testANoteGoesBeyondTheLoopsOfItsState() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> A : again\nnote right of A : note")
        let loopText = try XCTUnwrap(laidOut.transitions[0].text)
        XCTAssertGreaterThan(laidOut.notes[0].frame.minX, loopText.frame.maxX)
    }
}
