import XCTest
@testable import MermaidDiagrams

final class StateDiagramLayoutEngineTests: XCTestCase {
    private func layout(_ source: String, limits: MermaidDiagramLimits = .standard) throws -> StateDiagramLayout {
        try StateDiagramUniformLayout.layout(source, limits: limits)
    }

    func testStatesFollowEachOtherDownInRanksAPeleRankGapApart() throws {
        let laidOut = try layout("stateDiagram-v2\n[*] --> Still\nStill --> Moving\nMoving --> [*]")
        let frames = laidOut.states.map(\.frame)
        XCTAssertEqual(laidOut.states.map(\.kind), [.start, .state, .state, .end])
        for (upper, lower) in zip(frames, frames.dropFirst()) {
            XCTAssertEqual(lower.minY - upper.maxY, 44, accuracy: 0.01)
            XCTAssertEqual(lower.midX, upper.midX, accuracy: 0.01, "A chain runs straight")
        }
    }

    func testEachDirectionTurnsTheFlow() throws {
        let source = "stateDiagram-v2\ndirection %@\n[*] --> A\nA --> B"
        func centers(_ direction: String) throws -> [CGPoint] {
            try layout(source.replacingOccurrences(of: "%@", with: direction)).states.map { state in CGPoint(x: state.frame.midX, y: state.frame.midY) }
        }
        let down = try centers("TB")
        XCTAssertTrue(down[0].y < down[1].y && down[1].y < down[2].y)
        let up = try centers("BT")
        XCTAssertTrue(up[0].y > up[1].y && up[1].y > up[2].y)
        let right = try centers("LR")
        XCTAssertTrue(right[0].x < right[1].x && right[1].x < right[2].x)
        let left = try centers("RL")
        XCTAssertTrue(left[0].x > left[1].x && left[1].x > left[2].x)
    }

    func testShapesHavePelesSizes() throws {
        let laidOut = try layout("stateDiagram-v2\nstate if_state <<choice>>\n[*] --> Still\nStill --> if_state\nif_state --> A\nA --> [*]")
        func size(of kind: StateDiagramStateKind) -> CGSize? {
            laidOut.states.first { state in state.kind == kind }?.frame.size
        }
        XCTAssertEqual(size(of: .start), CGSize(width: 14, height: 14))
        XCTAssertEqual(size(of: .end), CGSize(width: 18, height: 18))
        XCTAssertEqual(size(of: .choice), CGSize(width: 30, height: 30))
        XCTAssertEqual(laidOut.states.first { state in state.name?.lines == ["Still"] }?.frame.size, CGSize(width: 5 * 8 + 32, height: 24 + 20))
        XCTAssertEqual(laidOut.states.first { state in state.name?.lines == ["A"] }?.frame.width, 56, "A box is at least 56 points wide")
    }

    func testABoxWithSeveralDescriptionsHasTheRestUnderItsName() throws {
        let state = try XCTUnwrap(layout("stateDiagram-v2\nA : one\nA : second one").states.first)
        let name = try XCTUnwrap(state.name)
        let details = try XCTUnwrap(state.details)
        XCTAssertEqual(name.lines, ["one"])
        XCTAssertEqual(details.lines, ["second one"])
        XCTAssertEqual(details.fontSize, 14)
        XCTAssertEqual(name.frame.minY - state.frame.minY, 10, accuracy: 0.01)
        XCTAssertEqual(details.frame.minY - name.frame.maxY, 14, accuracy: 0.01)
        XCTAssertEqual(state.frame.height, 24 + 20 + 14 + 21, accuracy: 0.01)
        XCTAssertEqual(state.frame.width, 10 * 7 + 32, accuracy: 0.01)
    }

    func testAForkIsABarAcrossTheFlowAsLongAsItsBusierSide() throws {
        let source = "stateDiagram-v2\n%@\nstate fork_state <<fork>>\n[*] --> fork_state\nfork_state --> A\nfork_state --> B\nfork_state --> C"
        let down = try layout(source.replacingOccurrences(of: "%@", with: ""))
        XCTAssertEqual(down.states.first { state in state.kind == .fork }?.frame.size, CGSize(width: 40 * 3 + 16, height: 8))
        let across = try layout(source.replacingOccurrences(of: "%@", with: "direction LR"))
        XCTAssertEqual(across.states.first { state in state.kind == .fork }?.frame.size, CGSize(width: 8, height: 40 * 3 + 16))
        let short = try layout("stateDiagram-v2\nstate join_state <<join>>\nA --> join_state\njoin_state --> B")
        XCTAssertEqual(short.states.first { state in state.kind == .join }?.frame.width, 72, "A bar is at least 72 points long")
    }

    func testTheTitleSitsAboveTheDiagram() throws {
        let laidOut = try layout("---\ntitle: Machine\n---\nstateDiagram-v2\n[*] --> A")
        let title = try XCTUnwrap(laidOut.title)
        XCTAssertEqual(title.lines, ["Machine"])
        XCTAssertEqual(title.frame.minY, 8, accuracy: 0.01)
        for state in laidOut.states { XCTAssertGreaterThanOrEqual(state.frame.minY, title.frame.maxY + 12 - 0.01) }
    }

    func testNothingOverlapsAndThePaddingSurroundsTheDrawing() throws {
        let laidOut = try layout("""
        stateDiagram-v2
            state if_state <<choice>>
            [*] --> IsPositive
            IsPositive --> if_state
            if_state --> False: if n < 0
            if_state --> True : if n >= 0
            False --> False : retry
            note right of True : a note beside True
            note left of False
                two lines
                of note
            end note
        """)
        let frames = laidOut.states.map(\.frame) + laidOut.notes.map(\.frame)
        for (index, frame) in frames.enumerated() {
            for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other), "\(frame) overlaps \(other)") }
            XCTAssertGreaterThanOrEqual(frame.minX, 8 - 0.01)
            XCTAssertGreaterThanOrEqual(frame.minY, 8 - 0.01)
            XCTAssertLessThanOrEqual(frame.maxX, laidOut.size.width - 8 + 0.01)
            XCTAssertLessThanOrEqual(frame.maxY, laidOut.size.height - 8 + 0.01)
        }
    }

    func testStartsComeFirstAndTheOthersInTheOrderTransitionsNameThem() throws {
        let diagram = try StateDiagramReading.stateDiagram("stateDiagram-v2\nA : first declared\nB : second\nC\n[*] --> B\nB --> A")
        XCTAssertEqual(StateDiagramLayoutEngine.flowOrder(of: diagram).map { index in diagram.states[index].identifier }, ["[*]", "B", "A", "C"])
    }

    func testAnEmptyDiagramIsOnlyItsPadding() throws {
        let laidOut = try layout("stateDiagram-v2\n")
        XCTAssertTrue(laidOut.states.isEmpty)
        XCTAssertEqual(laidOut.size, CGSize(width: 16, height: 16))
    }

    func testCompositeStatesAndTheLayoutLimitAreRefused() throws {
        XCTAssertThrowsError(try layout("stateDiagram-v2\nstate Moving {\n  slow --> fast\n}")) { error in
            XCTAssertEqual(error as? StateDiagramLayoutError, .compositeStatesNotLaidOut)
        }
        var limits = MermaidDiagramLimits.standard
        limits.maximumLayoutPointCount = 3
        XCTAssertThrowsError(try layout("stateDiagram-v2\nA --> B\nB --> C\nA --> C\nC --> D", limits: limits)) { error in
            XCTAssertEqual(error as? StateDiagramLayoutError, .tooManyLayoutPoints(limit: 3))
        }
    }
}
