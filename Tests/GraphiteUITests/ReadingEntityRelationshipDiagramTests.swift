import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingEntityRelationshipDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsAnEntityRelationshipDiagram: Error {}

    private func drawn(_ source: String) throws -> ReadingEntityRelationshipDiagram {
        guard case .entityRelationship(let diagram) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            throw NotDrawnAsAnEntityRelationshipDiagram()
        }
        return diagram
    }

    func testAnEntityRelationshipDiagramIsLaidOutInTheNotesTextSize() throws {
        let diagram = try drawn("erDiagram\n  CUSTOMER ||--o{ ORDER : places\n  ORDER {\n    int id PK\n  }")
        XCTAssertEqual(diagram.layout.font.size, 17)
        XCTAssertEqual(diagram.layout.entities.count, 2)
        XCTAssertEqual(diagram.layout.entities[1].rows.count, 1)
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try drawn("---\ntitle: Orders\n---\nerDiagram\naccDescr: Who orders what\nA")
        XCTAssertEqual(titled.title, "Orders")
        XCTAssertEqual(titled.description, "Who orders what")
        XCTAssertEqual(try drawn("erDiagram\naccTitle: Named\nA").title, "Named")
        let summarized = try drawn("erDiagram\nc[CUSTOMER] {\n string name\n}\nc ||--o{ ORDER : places\nORDER ||--|| INVOICE : \"\"")
        XCTAssertNil(summarized.description)
        XCTAssertEqual(summarized.summary, ["CUSTOMER", "ORDER", "INVOICE", "CUSTOMER places ORDER", "ORDER INVOICE"])
    }

    func testADiagramWithSubgraphsStaysCode() {
        XCTAssertNil(ReadingDiagram(source: "erDiagram\nsubgraph group\nA\nend", typography: typography))
    }

    func testADiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "erDiagram\nCUSTOMER {\n string name"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 2, problem: .unclosedAttributeBlock(entity: "CUSTOMER"))))
    }

    func testEveryEntityRelationshipFailureIsExplained() {
        let failures: [ReadingDiagramFailure] = [
            .entityRelationshipLayout(.tooManyLayoutPoints(limit: 1)), .entityRelationshipLayout(.subgraphsNotLaidOut),
        ] + [MermaidSyntaxProblem.expectedRelationshipLine, .expectedCardinality, .expectedRelationshipLabel, .expectedAttribute,
             .unclosedAttributeBlock(entity: "BOOK")].map { problem in .reading(.invalidSyntax(line: 1, problem: problem)) }
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
        XCTAssertEqual(ReadingDiagramFailure.entityRelationshipLayout(.subgraphsNotLaidOut).explanation,
                       ReadingDiagramFailure.layout(.subgraphsNotLaidOut).explanation)
    }
}
