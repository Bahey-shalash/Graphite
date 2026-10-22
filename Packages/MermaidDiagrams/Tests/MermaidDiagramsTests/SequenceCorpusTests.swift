import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's sequence diagram documentation examples, as Pele's benchmark collects them: every one is read, and the
/// ones that use statements not laid out yet say which.
final class SequenceCorpusTests: XCTestCase {
    func testEveryDocumentationExampleIsReadAndTheOnesNotLaidOutSayWhy() throws {
        let examples = try SequenceCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 38)
        var statementsNotLaidOutByExample: [Int: Set<SequenceStatementNotLaidOut>] = [:]
        for (index, example) in examples.enumerated() {
            let diagram = try SequenceReading.sequence(example)
            XCTAssertFalse(diagram.participants.isEmpty, "Example \(index)")
            if !diagram.statementsNotLaidOut.isEmpty { statementsNotLaidOutByExample[index] = diagram.statementsNotLaidOut }
        }
        let attributes: Set<SequenceStatementNotLaidOut> = [.participantAttributes]
        XCTAssertEqual(statementsNotLaidOutByExample, [
            5: attributes, 6: attributes, 7: attributes, 8: attributes, 9: attributes, 10: attributes, 12: attributes, 13: attributes, 14: attributes,
            15: [.participantCreation, .participantDestruction], 16: [.box], 17: [.centralConnection], 36: [.participantMenu], 37: [.participantMenu],
        ])
    }
}
