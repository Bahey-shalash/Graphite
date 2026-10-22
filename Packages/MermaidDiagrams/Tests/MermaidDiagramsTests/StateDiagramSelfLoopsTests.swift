import XCTest
@testable import MermaidDiagrams

final class StateDiagramSelfLoopsTests: XCTestCase {
    private func layout(_ source: String) throws -> StateDiagramLayout {
        try StateDiagramUniformLayout.layout(source)
    }

    func testALoopHangsOffTheRightOfAStateWithItsTextBeyond() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> B\nB --> B : again")
        let state = laidOut.states[1].frame
        let loop = laidOut.transitions[1]
        XCTAssertEqual(loop.path.start.x, state.maxX, accuracy: 0.01)
        XCTAssertEqual(loop.arrow.tip.x, state.maxX, accuracy: 0.01)
        XCTAssertLessThan(loop.path.start.y, loop.arrow.tip.y, "It leaves above and comes back below")
        XCTAssertTrue(loop.path.allPoints.allSatisfy { point in point.x >= state.maxX - 0.01 })
        let text = try XCTUnwrap(loop.text)
        XCTAssertEqual(text.frame.minX, state.maxX + 26 + 4 + 6, accuracy: 0.01)
        XCTAssertEqual(text.center.y, state.midY, accuracy: 0.01)
    }

    func testEachNextLoopReachesFurther() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> A\nA --> A")
        let reaches = laidOut.transitions.map { transition in transition.path.allPoints.map(\.x).max() ?? 0 }
        XCTAssertEqual(reaches[1] - reaches[0], 8, accuracy: 0.01)
    }

    func testInAFlowThatRunsAcrossALoopHangsBelow() throws {
        let laidOut = try layout("stateDiagram-v2\ndirection LR\nA --> B\nB --> B : again")
        let state = laidOut.states[1].frame
        let loop = laidOut.transitions[1]
        XCTAssertEqual(loop.path.start.y, state.maxY, accuracy: 0.01)
        XCTAssertTrue(loop.path.allPoints.allSatisfy { point in point.y >= state.maxY - 0.01 })
        XCTAssertGreaterThan(try XCTUnwrap(loop.text).frame.minY, state.maxY + 26 * 0.75)
    }

    func testAStateWithALoopStaysInLineWithItsTransitions() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> B\nB --> C\nB --> B : a long text on the loop")
        XCTAssertEqual(laidOut.states[0].frame.midX, laidOut.states[1].frame.midX, accuracy: 0.01)
        XCTAssertEqual(laidOut.states[2].frame.midX, laidOut.states[1].frame.midX, accuracy: 0.01)
    }

    func testTheRoomOfLoopsCoversTheirReachAndText() {
        let extent = StateDiagramSelfLoops.extent(textSizes: [CGSize(width: 40, height: 21), nil], flowIsVertical: true)
        XCTAssertEqual(extent.room, 26 + 8 + 40 + 12)
        XCTAssertEqual(extent.textAlong, 21)
        XCTAssertEqual(StateDiagramSelfLoops.extent(textSizes: [], flowIsVertical: true).room, 0)
    }
}
