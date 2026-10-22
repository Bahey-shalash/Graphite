import XCTest
import MermaidDiagrams
@testable import GraphiteUI

/// A ```mermaid block holding a state diagram, as the reading view builds it.
final class ReadingStateDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsAStateDiagram: Error {}

    private func stateDiagram(_ source: String) throws -> ReadingStateDiagram {
        guard case .stateDiagram(let diagram) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsAStateDiagram()
        }
        return diagram
    }

    func testAStateDiagramIsLaidOutInTheNotesTextSize() throws {
        for keyword in ["stateDiagram", "stateDiagram-v2"] {
            let diagram = try stateDiagram("\(keyword)\n  [*] --> Still\n  Still --> Moving : push\n  Moving --> [*]")
            XCTAssertEqual(diagram.layout.font.size, 17)
            XCTAssertEqual(diagram.layout.states.map(\.kind), [.start, .state, .state, .end])
            XCTAssertEqual(diagram.stateNames, ["Still", "Moving"])
        }
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try stateDiagram("---\ntitle: Front title\n---\nstateDiagram-v2\naccDescr: How it goes\n[*] --> A")
        XCTAssertEqual(titled.title, "Front title")
        XCTAssertEqual(titled.description, "How it goes")
        XCTAssertEqual(try stateDiagram("stateDiagram-v2\naccTitle: Named\nA").title, "Named")
        XCTAssertNil(try stateDiagram("stateDiagram-v2\nA").description)
    }

    func testAStateDiagramWithCompositeStatesStaysCode() {
        XCTAssertNil(ReadingDiagram(source: "stateDiagram-v2\n[*] --> Active\nstate Active {\n  [*] --> On\n  --\n  [*] --> Off\n}", typography: typography))
        XCTAssertNil(ReadingDiagram(source: "stateDiagram-v2\nstate First {\n  [*] --> second\n}", typography: typography))
    }

    func testAStateDiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "stateDiagram-v2\nA\nnote right of A\nnever ended"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 3, problem: .unclosedNote)))
    }
}
