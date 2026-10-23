import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's Sankey documentation examples and the spec's energy flows read and laid out, and the benchmark's
/// generated flows.
final class SankeyCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testTheDocumentationExamplesAreDrawnBarThoseWithOptionsNotDrawnYet() throws {
        let examples = try SankeyCorpus.documentationExamples()
        var refused: [Int] = []
        for (index, example) in examples.enumerated() {
            let diagram = try SankeyReading.diagram(example)
            do {
                let layout = try SankeyLayoutEngine.layout(diagram, typography: typography)
                XCTAssertEqual(layout.nodes.count, diagram.nodes.count)
                XCTAssertTrue(layout.nodes.allSatisfy { node in CGRect(origin: .zero, size: layout.size).contains(node.frame) }, example)
            } catch {
                XCTAssertEqual(error, .optionsNotDrawn)
                refused.append(index)
            }
        }
        XCTAssertEqual(refused, [5, 7], "labelStyle: outlined, and nodeColors")
    }

    func testTheEnergyFlowsAreLaidOutWithTheirBarsApart() throws {
        let layout = try SankeyLayoutEngine.layout(try SankeyReading.diagram("sankey-beta\n\n " + SankeyCorpus.energyRows()), typography: typography)
        XCTAssertEqual(layout.links.count, 70)
        assertBarsApart(layout)
    }

    func testTheGeneratedFlowsAreLaidOutWithTheirBarsApart() throws {
        for (layerCount, nodesPerLayer) in [(5, 10), (10, 30)] {
            let diagram = try SankeyReading.diagram(SankeyCorpus.generated(layerCount: layerCount, nodesPerLayer: nodesPerLayer))
            XCTAssertEqual(diagram.links.count, (layerCount - 1) * nodesPerLayer * 2)
            assertBarsApart(try SankeyLayoutEngine.layout(diagram, typography: typography))
        }
    }

    /// No two bars of one column overlap, and every bar is on the page.
    private func assertBarsApart(_ layout: SankeyLayout, file: StaticString = #filePath, line: UInt = #line) {
        let columns = Dictionary(grouping: layout.nodes.map(\.frame)) { frame in frame.minX }
        for frames in columns.values {
            let sorted = frames.sorted { first, second in first.minY < second.minY }
            for (upper, lower) in zip(sorted, sorted.dropFirst()) {
                XCTAssertLessThanOrEqual(upper.maxY, lower.minY + 0.001, file: file, line: line)
            }
        }
        XCTAssertTrue(layout.nodes.allSatisfy { node in CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.001, dy: -0.001).contains(node.frame) },
                      file: file, line: line)
    }
}
