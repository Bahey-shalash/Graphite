import XCTest
@testable import MermaidDiagrams
@testable import MermaidDiagramsBenchmark

/// Mermaid's documentation examples, all read and laid out, so that none crashes and each that is not drawn says why.
final class FlowchartCorpusTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    func testEveryDocumentationExampleIsDrawnOrRefusedWithAReason() throws {
        let examples = try FlowchartCorpus.documentationExamples()
        XCTAssertEqual(examples.count, 114)
        var drawnCount = 0
        var refusals: [String: Int] = [:]
        for example in examples {
            do {
                guard case .flowchart(let diagram) = try MermaidDiagramReader.read(example, limits: .standard) else { continue }
                let layout = try FlowchartLayoutEngine.layout(diagram, typography: typography, limits: .standard)
                XCTAssertGreaterThan(layout.size.width, 0)
                drawnCount += 1
            } catch let error as MermaidDiagramReadError {
                refusals["\(error)", default: 0] += 1
            } catch let error as FlowchartLayoutError {
                refusals["\(error)", default: 0] += 1
            }
        }
        // The example with a collapsed subgraph is not laid out yet; the counts only rise.
        XCTAssertGreaterThanOrEqual(drawnCount, 113, "Refused: \(refusals)")
        print("FLOWCHART-CORPUS drawn \(drawnCount) of \(examples.count); refused \(refusals)")
    }

    func testTheGeneratedGroupsAreDrawnEachNodeInsideItsBox() throws {
        guard case .flowchart(let diagram) = try MermaidDiagramReader.read(FlowchartCorpus.groups(pairCount: 4, nodesPerGroup: 5), limits: .standard) else {
            return XCTFail("A flowchart")
        }
        XCTAssertEqual(diagram.subgraphs.count, 8)
        let layout = try FlowchartLayoutEngine.layout(diagram, typography: typography, limits: .standard)
        XCTAssertEqual(layout.nodes.count, 40)
        XCTAssertEqual(layout.clusters.map(\.depth), [0, 1, 0, 1, 0, 1, 0, 1])
        // The nodes that stand for groups (`outer0 --> outer1`) are not drawn, so the drawn nodes skip them.
        let groupNodes = Set(diagram.subgraphs.compactMap(\.representingNodeIndex))
        let drawnIndices = diagram.nodes.indices.filter { node in !groupNodes.contains(node) }
        for (index, subgraph) in diagram.subgraphs.enumerated() {
            for node in subgraph.nodeIndices {
                let drawn = try XCTUnwrap(drawnIndices.firstIndex(of: node))
                XCTAssertTrue(layout.clusters[index].frame.contains(layout.nodes[drawn].frame))
            }
        }
        for (index, box) in layout.clusters.enumerated() where box.depth == 0 {
            for other in layout.clusters[(index + 1)...] where other.depth == 0 { XCTAssertFalse(box.frame.intersects(other.frame)) }
        }
    }

    func testTheGeneratedTreesAndMeshesAreDrawn() throws {
        for source in [FlowchartCorpus.tree(nodeCount: 50), FlowchartCorpus.mesh(nodeCount: 50, extraEdgeCount: 20),
                       FlowchartCorpus.tree(nodeCount: 500), FlowchartCorpus.mesh(nodeCount: 500, extraEdgeCount: 200)] {
            guard case .flowchart(let diagram) = try MermaidDiagramReader.read(source, limits: .standard) else { return XCTFail("A flowchart") }
            let layout = try FlowchartLayoutEngine.layout(diagram, typography: typography, limits: .standard)
            XCTAssertEqual(layout.nodes.count, diagram.nodes.count)
            for (index, node) in layout.nodes.enumerated() {
                for other in layout.nodes[(index + 1)...] { XCTAssertFalse(node.frame.intersects(other.frame)) }
            }
        }
    }
}
