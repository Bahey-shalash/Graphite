import XCTest
@testable import MermaidDiagrams

final class StateDiagramEdgePortsTests: XCTestCase {
    private func layout(_ source: String) throws -> StateDiagramLayout {
        try StateDiagramUniformLayout.layout(source)
    }

    func testATransitionRunsFromItsSourcesSideToAnArrowOnItsTargetsSide() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> B")
        let source = laidOut.states[0].frame
        let target = laidOut.states[1].frame
        let transition = laidOut.transitions[0]
        XCTAssertEqual(transition.path.start, CGPoint(x: source.midX, y: source.maxY))
        XCTAssertEqual(transition.arrow.tip, CGPoint(x: target.midX, y: target.minY))
        XCTAssertEqual(transition.arrow.direction, CGVector(dx: 0, dy: 1))
        XCTAssertEqual(transition.arrow.arrowhead, .arrow)
        let lineEnd = try XCTUnwrap(transition.path.allPoints.last)
        XCTAssertEqual(lineEnd.y, target.minY - DiagramEdgeMark.lineTrim(for: .arrow), accuracy: 0.01, "The line stops where the arrow begins")
    }

    func testTransitionsMeetingOneSideOfABoxSpreadAlongItClearOfItsCorners() throws {
        let laidOut = try layout("stateDiagram-v2\nLongStateName --> B\nLongStateName --> C\nLongStateName --> D")
        let source = laidOut.states[0].frame
        let starts = laidOut.transitions.map(\.path.start.x).sorted()
        XCTAssertEqual(starts[1] - starts[0], 20, accuracy: 0.01)
        XCTAssertEqual(starts[2] - starts[1], 20, accuracy: 0.01)
        XCTAssertEqual(starts[1], source.midX, accuracy: 0.01)
    }

    func testOnAShortSideTheTransitionsCloseUp() {
        XCTAssertEqual(StateDiagramEdgePorts.offsets(count: 3, placement: .spread, sideLength: 44), [-10, 0, 10])
        XCTAssertEqual(StateDiagramEdgePorts.offsets(count: 3, placement: .middle, sideLength: 44), [0, 0, 0])
    }

    func testAStartAndAChoiceAreMetInTheMiddleOfTheirSides() throws {
        let laidOut = try layout("stateDiagram-v2\nstate pick <<choice>>\n[*] --> pick\npick --> A\npick --> B")
        let choice = try XCTUnwrap(laidOut.states.first { state in state.kind == .choice }?.frame)
        let leaving = laidOut.transitions.dropFirst().map(\.path.start)
        XCTAssertEqual(leaving, [CGPoint(x: choice.midX, y: choice.maxY), CGPoint(x: choice.midX, y: choice.maxY)])
        let start = try XCTUnwrap(laidOut.states.first { state in state.kind == .start }?.frame)
        XCTAssertEqual(laidOut.transitions[0].path.start, CGPoint(x: start.midX, y: start.maxY))
    }

    func testTransitionsMeetABarWhereTheirLinesComeFromShortOfItsEnds() throws {
        let laidOut = try layout("""
        stateDiagram-v2
            state fork_state <<fork>>
            [*] --> fork_state
            fork_state --> State2
            fork_state --> State3
            fork_state --> State4
        """)
        let bar = try XCTUnwrap(laidOut.states.first { state in state.kind == .fork }?.frame)
        let leaving = laidOut.transitions.dropFirst().map(\.path.start)
        XCTAssertEqual(Set(leaving.map(\.x)).count, 3, "Each meets the bar where it comes from")
        for point in leaving {
            XCTAssertEqual(point.y, bar.maxY, accuracy: 0.01)
            XCTAssertGreaterThanOrEqual(point.x, bar.minX + 6 - 0.01)
            XCTAssertLessThanOrEqual(point.x, bar.maxX - 6 + 0.01)
        }
    }

    func testATransitionsTextSitsOnItsOwnRankBetweenItsStates() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> B : go on")
        let text = try XCTUnwrap(laidOut.transitions[0].text)
        XCTAssertEqual(text.lines, ["go on"])
        XCTAssertEqual(text.fontSize, 14)
        XCTAssertGreaterThan(text.frame.minY, laidOut.states[0].frame.maxY)
        XCTAssertLessThan(text.frame.maxY, laidOut.states[1].frame.minY)
    }

    func testATransitionBackUpACycleRunsUpward() throws {
        let laidOut = try layout("stateDiagram-v2\nA --> B\nB --> A")
        let back = laidOut.transitions[1]
        XCTAssertEqual(back.arrow.tip.y, laidOut.states[0].frame.maxY, accuracy: 0.01)
        XCTAssertEqual(back.arrow.direction.dy, -1, accuracy: 0.01)
    }
}
