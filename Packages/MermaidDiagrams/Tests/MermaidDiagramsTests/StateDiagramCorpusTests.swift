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
}
