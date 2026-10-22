import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingSequenceShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsASequenceDiagram: Error {}

    private func sequence(_ body: String) throws -> ReadingSequence {
        guard case .sequence(let sequence) = try XCTUnwrap(ReadingDiagram(source: "sequenceDiagram\n" + body, typography: typography)) else {
            throw NotDrawnAsASequenceDiagram()
        }
        return sequence
    }

    func testEachLineOfTextIsCenteredOnItsLineOfTheBlock() throws {
        let sequence = try sequence("Alice->>Bob: one<br>two")
        let text = try XCTUnwrap(sequence.layout.messages.first?.text)
        let lines = sequence.shapes.messageTextLines
        XCTAssertEqual(lines.map(\.text), ["one", "two"])
        XCTAssertEqual(lines[0].center.x, text.center.x)
        XCTAssertEqual(lines[1].center.y - lines[0].center.y, text.lineHeight)
        XCTAssertEqual(lines[0].font.size, 14)
    }

    func testBlockKeywordsAreBoldAndSmallestAndTheirTextsSeparate() throws {
        let sequence = try sequence("loop Every minute\nAlice->>Bob: Hi\nend")
        XCTAssertEqual(sequence.shapes.blockKeywordLines.map(\.text), ["loop"])
        XCTAssertEqual(sequence.shapes.blockKeywordLines.map(\.isBold), [true])
        XCTAssertEqual(sequence.shapes.blockKeywordLines.first?.font.size, 12)
        XCTAssertEqual(sequence.shapes.blockTextLines.map(\.text), ["[Every minute]"])
        XCTAssertFalse(sequence.shapes.blockTabs.isEmpty)
    }

    func testNumbersParticipantsNotesAndTheTitleHaveTheirOwnLines() throws {
        let sequence = try sequence("title Plan\nautonumber\nAlice->>Bob: Hi\nNote over Bob: Thinks")
        XCTAssertEqual(sequence.shapes.numberTextLines.map(\.text), ["1"])
        XCTAssertEqual(sequence.shapes.topTextLines.map(\.text), ["Thinks", "Alice", "Bob", "Alice", "Bob", "Plan"])
        XCTAssertEqual(sequence.shapes.topTextLines.last?.isBold, true)
        XCTAssertFalse(sequence.shapes.numberBadges.isEmpty)
        XCTAssertFalse(sequence.shapes.notes.isEmpty)
    }

    func testHighlightsAndActivationsKeepTheirOrder() throws {
        let sequence = try sequence("rect rgb(0, 0, 255)\nrect\nAlice->>+Bob: Hi\nAlice->>+Bob: Again\nBob-->>-Alice: Yes\nBob-->>-Alice: Yes\nend\nend")
        XCTAssertEqual(sequence.shapes.highlights.map { highlight in highlight.color.map { color in [color.red, color.green, color.blue] } }, [[0, 0, 1], nil])
        XCTAssertEqual(sequence.shapes.activations.count, 2)
        XCTAssertGreaterThan(sequence.shapes.activations[1].boundingRect.minX, sequence.shapes.activations[0].boundingRect.minX,
                             "The nested activation is drawn over the one it is in")
    }
}
