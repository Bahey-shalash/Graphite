import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingSequenceTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsASequenceDiagram: Error {}

    private func sequence(_ source: String) throws -> ReadingSequence {
        guard case .sequence(let sequence) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsASequenceDiagram()
        }
        return sequence
    }

    func testASequenceDiagramIsLaidOutInTheNotesTextSize() throws {
        let sequence = try sequence("sequenceDiagram\n  participant A as Alice\n  A->>Bob: Hi")
        XCTAssertEqual(sequence.layout.font.size, 17)
        XCTAssertEqual(sequence.layout.participants.count, 4)
        XCTAssertEqual(sequence.participantNames, ["Alice", "Bob"])
    }

    func testAccessibilityTextComesFromTheDiagramOrItsParticipantsAndMessages() throws {
        let described = try sequence("---\ntitle: Front title\n---\nsequenceDiagram\naccDescr: How it goes\nA->>B: Hi")
        XCTAssertEqual(described.title, "Front title")
        XCTAssertEqual(described.accessibilityValue, "How it goes")
        let titled = try sequence("sequenceDiagram\naccTitle: Named\ntitle Shown\nAlice->>Bob: Hello<br>there\nBob-->>Alice:")
        XCTAssertEqual(titled.title, "Named")
        XCTAssertEqual(titled.accessibilityValue, "Alice, Bob. Alice to Bob: Hello there. Bob to Alice")
    }

    func testADiagramWithStatementsNotLaidOutStaysCode() {
        for statement in ["box Team\nparticipant A\nend", "create participant C\nA->>C: Hi", "A-|\\B: Half", "link A: Wiki @ https://example.com",
                          "participant A@{ \"type\": \"database\" }", "A()->>B: Circle", "destroy A\nA->>B: Bye"] {
            XCTAssertNil(ReadingDiagram(source: "sequenceDiagram\n\(statement)", typography: typography), statement)
        }
    }

    func testASequenceDiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "sequenceDiagram\nloop forever\nA->>B: Hi"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .sequence(.unclosedBlock(keyword: "loop")))))
    }
}
