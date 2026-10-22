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
        let blocks = try await build("```mermaid\ngantt\n  title Plan\n```").blocks
        guard case .markdown(_, let text) = blocks.first else { return XCTFail("Shown as code") }
        XCTAssertEqual(text, "```mermaid\ngantt\n  title Plan\n```")
    }

    func testASequenceDiagramBecomesADiagramBlockAndOneWithABoxStaysCode() async throws {
        let drawn = try await build("Before\n\n```mermaid\nsequenceDiagram\n  Alice->>Bob: Hi\n```\n\nAfter").blocks
        XCTAssertEqual(drawn.count, 3)
        guard case .diagram(_, .sequence(let sequence)) = drawn[1] else { return XCTFail("The sequence diagram is drawn") }
        XCTAssertEqual(sequence.participantNames, ["Alice", "Bob"])
        let boxed = try await build("```mermaid\nsequenceDiagram\n  box Team\n  participant A\n  end\n```").blocks
        guard case .markdown = boxed.first else { return XCTFail("A diagram with a box stays code") }
    }

    func testAFlowchartInACalloutIsDrawnInsideIt() async throws {
        let blocks = try await build("> [!example] Flow\n> ```mermaid\n> flowchart TD\n> A --> B\n> ```").blocks
        guard case .callout(_, _, _, _, let body) = blocks.first, case .diagram = body.first else { return XCTFail("Drawn in the callout") }
    }

    func testTheFontOfTheDiagramChangesWhatTheReadingViewReloadsFor() {
        var configuration = ReadingConfiguration()
        let systemFontHash = configuration.hashValueForReload
        configuration.diagramFontPostScriptName = "Georgia"
        XCTAssertNotEqual(configuration.hashValueForReload, systemFontHash)
    }
}
