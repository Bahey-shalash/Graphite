import XCTest
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingSankeyDiagramTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsASankeyDiagram: Error {}

    private func sankey(_ source: String) throws -> ReadingSankeyDiagram {
        guard case .sankey(let diagram) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsASankeyDiagram() }
        return diagram
    }

    func testASankeyDiagramIsLaidOutInTheNotesTextSize() throws {
        let diagram = try sankey("---\ntitle: Energy\n---\nsankey-beta\nCoal,Solid,75.571\nSolid,Industry,46.477")
        XCTAssertEqual(diagram.layout.font.size, 17)
        XCTAssertEqual(diagram.layout.title?.fontSize, 17)
        XCTAssertEqual(diagram.layout.labels.first?.name.fontSize, 15, "Seven eighths of the text size, rounded")
        XCTAssertEqual(diagram.layout.nodes.count, 3)
    }

    func testAScreenReaderHearsTheTitleAndEachFlow() throws {
        let diagram = try sankey("---\ntitle: Energy\n---\nsankey\nCoal,Solid,75.571\nSolid,Industry,46\nSolid,Waste,none")
        XCTAssertEqual(diagram.title, "Energy")
        XCTAssertEqual(diagram.flowSummaries, ["Coal to Solid: 75.57", "Solid to Industry: 46", "Solid to Waste"])
        XCTAssertNil(try sankey("sankey\na,b,1").title)
    }

    func testCircularLinksAndOptionsNotDrawnYetKeepTheBlockAsCode() {
        XCTAssertNil(ReadingDiagram(source: "sankey\na,b,1\nb,a,1", typography: typography))
        XCTAssertNil(ReadingDiagram(source: "---\nconfig:\n  sankey:\n    labelStyle: outlined\n---\nsankey\na,b,1", typography: typography))
    }

    func testASankeyDiagramThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "sankey\na,b,1\nc,d"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 3, problem: .expectedSankeyFields)))
        let failures: [ReadingDiagramFailure] = [.reading(.invalidSyntax(line: 1, problem: .expectedSankeyFields)),
                                                 .reading(.invalidSyntax(line: 1, problem: .expectedSeriesValues)),
                                                 .reading(.invalidSyntax(line: 1, problem: .unclosedQuotation))]
        XCTAssertEqual(Set(failures.map(\.explanation)).count, failures.count)
    }
}
