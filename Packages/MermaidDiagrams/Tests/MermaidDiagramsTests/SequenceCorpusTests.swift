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

    func testEveryExampleWithoutStatementsNotLaidOutIsLaidOutInsideItsSize() throws {
        let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
        var laidOutCount = 0
        for (index, example) in try SequenceCorpus.documentationExamples().enumerated() {
            let diagram = try SequenceReading.sequence(example)
            guard diagram.statementsNotLaidOut.isEmpty else {
                XCTAssertThrowsError(try SequenceLayoutEngine.layout(diagram, typography: typography), "Example \(index)")
                continue
            }
            let layout = try SequenceLayoutEngine.layout(diagram, typography: typography)
            laidOutCount += 1
            let page = CGRect(origin: .zero, size: layout.size)
            let texts = layout.participants.map(\.text) + layout.notes.map(\.text) + layout.messages.compactMap(\.text)
            for frame in layout.participants.map(\.frame) + layout.notes.map(\.frame) + layout.blocks.map(\.frame) + texts.map(\.frame) {
                XCTAssertTrue(page.insetBy(dx: -0.5, dy: -0.5).contains(frame), "Example \(index): \(frame) inside \(page)")
            }
            XCTAssertEqual(layout.participants.count, 2 * diagram.participants.count, "Example \(index)")
        }
        XCTAssertEqual(laidOutCount, 24)
    }

    func testTheGeneratedConversationIsLaidOutWithEveryMessageNoteAndLoop() throws {
        let diagram = try SequenceReading.sequence(SequenceCorpus.conversation(participantCount: 10, messageCount: 200))
        let layout = try SequenceLayoutEngine.layout(diagram, typography: DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16)))
        XCTAssertEqual(layout.messages.count, 200)
        XCTAssertEqual(layout.notes.count, 20)
        XCTAssertEqual(layout.blocks.count, 10)
        XCTAssertEqual(layout.messages.last?.number?.text.lines, ["200"])
    }
}
