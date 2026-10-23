import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's mindmap documentation examples, all read and laid out, and the benchmark's generated trees.
final class MindmapCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawn() throws {
        let examples = try MindmapCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 13)
        for example in examples {
            let layout = MindmapLayoutEngine.layout(try MindmapReading.mindmap(example), typography: typography)
            XCTAssertGreaterThan(layout.size.width, 0)
            XCTAssertEqual(layout.edges.count, layout.nodes.count - 1)
        }
    }

    func testTheGeneratedTreesAreDrawnWithoutOverlap() throws {
        for nodeCount in [50, 500] {
            let diagram = try MindmapReading.mindmap(MindmapCorpus.tree(nodeCount: nodeCount))
            XCTAssertEqual(diagram.nodes.count, nodeCount)
            let last = try XCTUnwrap(diagram.nodes.first { node in node.identifier == "Node \(nodeCount - 1)" })
            XCTAssertEqual(last.parentIndex.map { parent in diagram.nodes[parent].identifier }, "Node \((nodeCount - 2) / 3)")
            let nodes = MindmapLayoutEngine.layout(diagram, typography: typography).nodes
            let sorted = nodes.map(\.frame).sorted { first, second in first.minY < second.minY }
            for (index, frame) in sorted.enumerated() {
                for other in sorted[(index + 1)...] {
                    if other.minY >= frame.maxY { break }
                    XCTAssertFalse(frame.intersects(other))
                }
            }
        }
    }
}
