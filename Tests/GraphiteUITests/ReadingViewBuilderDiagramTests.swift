import XCTest
import GraphiteCore
import GraphiteIndex
@testable import GraphiteUI
import GraphiteTestSupport

/// A ```mermaid block in the reading view: a flowchart becomes a diagram block of its own, built with the other blocks
/// off the main actor; a type not drawn natively stays code.
final class ReadingViewBuilderDiagramTests: XCTestCase {
    private var vault: URL!
    private var index: VaultIndex!

    override func setUp() async throws {
        vault = try TemporaryVault.make(prefix: "DiagramVault", for: self).root
        index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
    }

    override func tearDown() async throws {
        index = nil
        try? FileManager.default.removeItem(at: vault) // Best-effort removal of a temporary folder.
    }

    private func build(_ source: String, configuration: ReadingConfiguration = ReadingConfiguration()) async throws -> ReadingViewBuild {
        try await ReadingViewBuilder().build(source: source, note: try VaultPath("Note.md"), root: vault, index: index, configuration: configuration)
    }

    func testAFlowchartBecomesADiagramBlockBetweenTheTextAroundIt() async throws {
        let blocks = try await build("Before\n\n```mermaid\nflowchart LR\n  A --> B\n```\n\nAfter").blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .diagram(_, .flowchart(let flowchart)) = blocks[1] else { return XCTFail("The flowchart is drawn") }
        XCTAssertEqual(flowchart.layout.nodes.count, 2)
        guard case .markdown(_, let after) = blocks[2] else { return XCTFail("Text follows") }
        XCTAssertEqual(after.trimmingCharacters(in: .whitespacesAndNewlines), "After")
    }

    func testTheDiagramIsLaidOutAtTheNotesTextSize() async throws {
        var configuration = ReadingConfiguration()
        configuration.textSize = 22
        let blocks = try await build("```mermaid\ngraph TD\nA\n```", configuration: configuration).blocks
        guard case .diagram(_, .flowchart(let flowchart)) = blocks.first else { return XCTFail("Drawn") }
        XCTAssertEqual(flowchart.layout.font.size, 22)
    }

    func testATypeNotDrawnYetStaysACodeBlock() async throws {
        let blocks = try await build("```mermaid\njourney\n  title My working day\n```").blocks
        guard case .markdown(_, let text) = blocks.first else { return XCTFail("Shown as code") }
        XCTAssertEqual(text, "```mermaid\njourney\n  title My working day\n```")
    }

    func testASequenceDiagramBecomesADiagramBlockAndOneWithABoxStaysCode() async throws {
        let drawn = try await build("Before\n\n```mermaid\nsequenceDiagram\n  Alice->>Bob: Hi\n```\n\nAfter").blocks
        XCTAssertEqual(drawn.count, 3)
        guard case .diagram(_, .sequence(let sequence)) = drawn[1] else { return XCTFail("The sequence diagram is drawn") }
        XCTAssertEqual(sequence.participantNames, ["Alice", "Bob"])
        let boxed = try await build("```mermaid\nsequenceDiagram\n  box Team\n  participant A\n  end\n```").blocks
        guard case .markdown = boxed.first else { return XCTFail("A diagram with a box stays code") }
    }

    func testAFlowchartWithSubgraphsBecomesADiagramBlockWithItsBoxes() async throws {
        let blocks = try await build("```mermaid\nflowchart LR\n  subgraph one [Group]\n    A --> B\n  end\n  B --> C\n```").blocks
        guard case .diagram(_, .flowchart(let flowchart)) = blocks.first else { return XCTFail("The flowchart is drawn") }
        XCTAssertEqual(flowchart.layout.clusters.count, 1)
        XCTAssertEqual(flowchart.layout.clusters[0].title?.lines, ["Group"])
    }

    func testAFlowchartWithACollapsedGroupStaysACodeBlock() async throws {
        let source = "```mermaid\nflowchart TD\n  subgraph one\n    A\n  end\n  one@{ view: collapsed }\n```"
        guard case .markdown(_, let text) = try await build(source).blocks.first else { return XCTFail("Shown as code") }
        XCTAssertEqual(text, source)
    }

    func testAFlowchartInACalloutIsDrawnInsideIt() async throws {
        let blocks = try await build("> [!example] Flow\n> ```mermaid\n> flowchart TD\n> A --> B\n> ```").blocks
        guard case .callout(_, _, _, _, let body) = blocks.first, case .diagram = body.first else { return XCTFail("Drawn in the callout") }
    }

    func testAClassDiagramBecomesADiagramBlockAndOneWithNamespacesStaysCode() async throws {
        let drawn = "```mermaid\nclassDiagram\n  Animal <|-- Duck\n```"
        let blocks = try await build(drawn + "\n\n```mermaid\nclassDiagram\nnamespace Shapes {\n  class Square\n}\n```").blocks
        XCTAssertEqual(blocks.count, 2)
        guard case .diagram(_, .classDiagram(let classDiagram)) = blocks[0] else { return XCTFail("The class diagram is drawn") }
        XCTAssertEqual(classDiagram.layout.classes.count, 2)
        guard case .markdown(_, let text) = blocks[1] else { return XCTFail("Shown as code") }
        XCTAssertEqual(text, "```mermaid\nclassDiagram\nnamespace Shapes {\n  class Square\n}\n```")
    }

    func testAnEntityRelationshipDiagramBecomesADiagramBlock() async throws {
        let blocks = try await build("Schema\n\n```mermaid\nerDiagram\n  CUSTOMER ||--o{ ORDER : places\n```").blocks
        XCTAssertEqual(blocks.count, 2)
        guard case .diagram(_, .entityRelationship(let diagram)) = blocks[1] else { return XCTFail("The entity relationship diagram is drawn") }
        XCTAssertEqual(diagram.layout.entities.count, 2)
    }

    func testTheFontOfTheDiagramChangesWhatTheReadingViewReloadsFor() {
        var configuration = ReadingConfiguration()
        let systemFontHash = configuration.hashValueForReload
        configuration.diagramFontPostScriptName = "Georgia"
        XCTAssertNotEqual(configuration.hashValueForReload, systemFontHash)
    }

    func testAStateDiagramBecomesADiagramBlockAndOneWithCompositeStatesStaysCode() async throws {
        let blocks = try await build("```mermaid\nstateDiagram-v2\n  [*] --> Still\n  Still --> [*]\n```").blocks
        guard case .diagram(_, .stateDiagram(let diagram)) = blocks.first else { return XCTFail("The state diagram is drawn") }
        XCTAssertEqual(diagram.layout.states.count, 3)
        let composite = try await build("```mermaid\nstateDiagram-v2\n  state A {\n    a --> b\n  }\n```").blocks
        guard case .markdown(_, let text) = composite.first else { return XCTFail("Shown as code") }
        XCTAssertEqual(text, "```mermaid\nstateDiagram-v2\n  state A {\n    a --> b\n  }\n```")
    }

    func testAnXYChartBecomesADiagramBlockAndOneWithoutSeriesShowsWhy() async throws {
        let blocks = try await build("```mermaid\nxychart-beta\n  x-axis [a, b]\n  bar [1, 2]\n```").blocks
        guard case .diagram(_, .xyChart(let chart)) = blocks.first else { return XCTFail("The XY chart is drawn") }
        XCTAssertEqual(chart.layout.bars.count, 2)
        let empty = try await build("```mermaid\nxychart\n  title \"Nothing\"\n```").blocks
        guard case .diagram(_, .unreadable(_, let failure)) = empty.first else { return XCTFail("Shown with why") }
        XCTAssertEqual(failure, .xyChartLayout(.noSeries))
    }

    func testASankeyDiagramBecomesADiagramBlockAndOneWithCircularLinksStaysCode() async throws {
        let blocks = try await build("```mermaid\nsankey-beta\nCoal,Solid,75.571\nSolid,Industry,46.477\n```").blocks
        guard case .diagram(_, .sankey(let sankey)) = blocks.first else { return XCTFail("The Sankey diagram is drawn") }
        XCTAssertEqual(sankey.layout.links.count, 2)
        let circular = try await build("```mermaid\nsankey\na,b,1\nb,a,1\n```").blocks
        guard case .markdown(_, let text) = circular.first else { return XCTFail("Shown as code") }
        XCTAssertEqual(text, "```mermaid\nsankey\na,b,1\nb,a,1\n```")
    }
}
