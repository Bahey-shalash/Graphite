import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's state diagram documentation examples, as Pele collects them: every one is read.
final class StateDiagramCorpusTests: XCTestCase {
    func testEveryDocumentationExampleIsRead() throws {
        let examples = try StateDiagramCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 22)
        let diagrams = try examples.map { example in try StateDiagramReading.stateDiagram(example) }
        XCTAssertEqual(diagrams.filter { diagram in !diagram.composites.isEmpty }.count, 7)
        XCTAssertEqual(diagrams.filter { diagram in !diagram.notes.isEmpty }.count, 1)
        XCTAssertEqual(diagrams.filter { diagram in diagram.states.contains { state in state.kind == .choice } }.count, 1)
        XCTAssertEqual(diagrams.filter { diagram in diagram.states.contains { state in state.kind == .fork } }.count, 1)
    }

    func testEveryDocumentationExampleIsLaidOutOrRefusedForItsCompositeStates() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        var laidOutCount = 0
        for example in try StateDiagramCorpus.documentationExamples() {
            let diagram = try StateDiagramReading.stateDiagram(example)
            do {
                let layout = try StateDiagramLayoutEngine.layout(diagram, typography: typography, limits: .standard)
                let frames = layout.states.map(\.frame) + layout.notes.map(\.frame)
                for (index, frame) in frames.enumerated() {
                    for other in frames[(index + 1)...] { XCTAssertFalse(frame.intersects(other), example) }
                }
                laidOutCount += 1
            } catch {
                XCTAssertEqual(error, .compositeStatesNotLaidOut)
                XCTAssertFalse(diagram.composites.isEmpty)
            }
        }
        XCTAssertEqual(laidOutCount, 15)
    }
}
