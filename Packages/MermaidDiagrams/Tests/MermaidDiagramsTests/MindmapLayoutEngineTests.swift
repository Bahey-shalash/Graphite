import XCTest
@testable import MermaidDiagrams

/// Pele's mindmap measurements, with text 8 points a character and 24 points a line.
final class MindmapLayoutEngineTests: XCTestCase {
    private let accuracy: CGFloat = 0.01
    private let font = DiagramFont(postScriptName: nil, size: 16)

    private func layout(_ source: String, title: String? = nil, limits: MermaidDiagramLimits = .standard) throws -> MindmapLayout {
        var diagram = try MindmapReading.mindmap(source, limits: limits)
        diagram.title = title
        return MindmapLayoutEngine.layout(diagram, measurer: UniformWidthTextMeasurer(), font: font)
    }

    func testEachOutlineTakesPelesSizeAroundItsText() throws {
        // Every text is 4 characters: 32 points wide and 24 high.
        let nodes = try layout("mindmap\n Root\n  Pill\n   leaf\n  b[Rect]\n  c(Rond)\n  d((Circ))\n  e)Clou(\n  f))Bang((\n  g{{Hexa}}").nodes
        XCTAssertEqual(nodes.map(\.outline), [.stadium, .pill, .text, .rectangle, .roundedRectangle, .circle, .cloud, .bang, .hexagon])
        let sizes = nodes.map(\.frame.size)
        XCTAssertEqual(sizes[0], CGSize(width: 32 + 48 * 0.5 + 36 - 8, height: 48))
        XCTAssertEqual(sizes[1], CGSize(width: 32 + 24, height: 30))
        XCTAssertEqual(sizes[2], CGSize(width: 32 + 12, height: 24))
        XCTAssertEqual(sizes[3], CGSize(width: 32 + 36, height: 48))
        XCTAssertEqual(sizes[4], CGSize(width: 32 + 36, height: 48))
        XCTAssertEqual(sizes[5], CGSize(width: 56, height: 56))
        XCTAssertEqual(sizes[6], CGSize(width: 32 + 36 + 32, height: 72))
        XCTAssertEqual(sizes[7], CGSize(width: 32 + 36 + 28, height: 72))
        XCTAssertEqual(sizes[8], CGSize(width: 32 + 36 + 24, height: 48))
        for node in nodes {
            XCTAssertEqual(node.text.center.x, node.frame.midX, accuracy: accuracy)
            XCTAssertEqual(node.text.center.y, node.frame.midY, accuracy: accuracy)
        }
    }

    func testTheRootIsInTheMiddleWithItsFirstBranchesRightAndTheRestLeft() throws {
        let nodes = try layout("mindmap\n root\n  one\n  two").nodes
        let root = nodes[0].frame
        XCTAssertEqual(nodes[1].frame.minX - root.maxX, 52, accuracy: accuracy)
        XCTAssertEqual(root.minX - nodes[2].frame.maxX, 52, accuracy: accuracy)
        XCTAssertEqual(nodes[1].frame.midY, root.midY, accuracy: accuracy)
        XCTAssertEqual(nodes[2].frame.midY, root.midY, accuracy: accuracy)
    }

    func testOneBranchGoesRight() throws {
        let nodes = try layout("mindmap\n root\n  only").nodes
        XCTAssertGreaterThan(nodes[1].frame.minX, nodes[0].frame.maxX)
    }

    func testBranchesSplitWhereTheTwoSidesAreClosestInHeight() {
        XCTAssertEqual(MindmapPlacement.rightBranchCount([1, 2, 3, 4], extents: [48, 24, 24, 24, 24]), 2)
        XCTAssertEqual(MindmapPlacement.rightBranchCount([1, 2, 3], extents: [48, 200, 24, 24]), 1)
        XCTAssertEqual(MindmapPlacement.rightBranchCount([1], extents: [48, 24]), 1)
        XCTAssertEqual(MindmapPlacement.rightBranchCount([], extents: [48]), 0)
    }

    func testDeeperLevelsAreAColumnFurtherOutOnTheirBranchsSide() throws {
        let nodes = try layout("mindmap\n root\n  right\n   deeper\n  left\n   deeper").nodes
        XCTAssertEqual(nodes[2].frame.minX - nodes[1].frame.maxX, 36, accuracy: accuracy)
        XCTAssertEqual(nodes[3].frame.minX - nodes[4].frame.maxX, 36, accuracy: accuracy)
        XCTAssertLessThan(nodes[4].frame.maxX, nodes[0].frame.minX)
    }

    func testSiblingsAreStackedEightApartAndTheirParentIsLevelWithTheirMiddle() throws {
        let nodes = try layout("mindmap\n R\n  P\n   a\n   b\n   c").nodes
        XCTAssertEqual(nodes[3].frame.minY - nodes[2].frame.maxY, 8, accuracy: accuracy)
        XCTAssertEqual(nodes[4].frame.minY - nodes[3].frame.maxY, 8, accuracy: accuracy)
        XCTAssertEqual(nodes[1].frame.midY, nodes[3].frame.midY, accuracy: accuracy)
        XCTAssertEqual(nodes[1].frame.midY, nodes[0].frame.midY, accuracy: accuracy)
    }

    func testASubtreeWithChildrenIsSetEighteenApartFromItsNeighbour() throws {
        let nodes = try layout("mindmap\n R\n  P\n   a\n    x\n   b").nodes
        XCTAssertEqual(nodes[4].frame.minY - nodes[2].frame.maxY, 18, accuracy: accuracy)
        XCTAssertEqual(nodes[3].frame.midY, nodes[2].frame.midY, accuracy: accuracy)
    }

    func testLinksRunFromAParentsSideToItsChildsInTheChildsBranch() throws {
        let layout = try layout("mindmap\n R\n  P\n   c)cloud(\n  left")
        XCTAssertEqual(layout.edges.count, 3)
        XCTAssertEqual(layout.edges.map(\.branchIndex), [0, 0, 1])
        let rootToPill = layout.edges[0].path
        XCTAssertEqual(rootToPill.start, CGPoint(x: layout.nodes[0].frame.maxX, y: layout.nodes[0].frame.midY))
        guard case .curve(let end, let firstControl, let secondControl) = rootToPill.segments.first else { return XCTFail("An S curve") }
        XCTAssertEqual(end, CGPoint(x: layout.nodes[1].frame.minX, y: layout.nodes[1].frame.midY))
        XCTAssertEqual(firstControl.x, (rootToPill.start.x + end.x) / 2, accuracy: accuracy)
        XCTAssertEqual(firstControl.y, rootToPill.start.y, accuracy: accuracy)
        XCTAssertEqual(secondControl.y, end.y, accuracy: accuracy)
        XCTAssertEqual(layout.edges[1].path.allPoints.last?.x ?? 0, layout.nodes[2].frame.minX + 2, accuracy: accuracy, "A cloud's outline is 2 points in")
        XCTAssertEqual(layout.edges[2].path.start.x, layout.nodes[0].frame.minX, accuracy: accuracy, "A link to the left leaves the left side")
    }

    func testTheDrawingStartsInsideThePaddingBelowTheTitle() throws {
        let plain = try layout("mindmap\n root\n  child")
        let bounds = plain.nodes.reduce(CGRect.null) { bounds, node in bounds.union(node.frame) }
        XCTAssertEqual(bounds.minX, 8, accuracy: accuracy)
        XCTAssertEqual(bounds.minY, 8, accuracy: accuracy)
        XCTAssertEqual(plain.size.width, (bounds.maxX + 8).rounded(.up))
        let titled = try layout("mindmap\n root\n  child", title: String(repeating: "T", count: 60))
        let title = try XCTUnwrap(titled.title)
        XCTAssertEqual(title.center.x, titled.size.width / 2, accuracy: accuracy)
        let titledBounds = titled.nodes.reduce(CGRect.null) { bounds, node in bounds.union(node.frame) }
        XCTAssertEqual(titledBounds.minY - title.frame.maxY, 16, accuracy: accuracy)
        XCTAssertEqual(titled.size.width, 60 * 8 + 16)
    }

    func testTheDocumentationsExampleHasNoOverlappingNodes() throws {
        let nodes = try layout("""
        mindmap
          root((mindmap))
            Origins
              Long history
              Popularisation
                British popular psychology author Tony Buzan
            Research
              On effectiveness<br/>and features
              On Automatic creation
                Uses
                    Creative techniques
                    Strategic planning
                    Argument mapping
            Tools
              Pen and paper
              Mermaid
        """).nodes
        for (index, node) in nodes.enumerated() {
            for other in nodes[(index + 1)...] { XCTAssertFalse(node.frame.intersects(other.frame)) }
        }
        XCTAssertEqual(nodes.filter { node in node.frame.minX > nodes[0].frame.maxX }.count + nodes.filter { node in node.frame.maxX < nodes[0].frame.minX }.count,
                       nodes.count - 1, "Every node but the root is on one side of it")
    }

    func testALongChainLaysOutWithoutRecursion() throws {
        let source = "mindmap\n" + (0..<2_000).map { depth in String(repeating: " ", count: depth) + "n\(depth)" }.joined(separator: "\n")
        var limits = MermaidDiagramLimits.standard
        limits.maximumSourceBytes = source.utf8.count
        let layout = try layout(source, limits: limits)
        XCTAssertEqual(layout.nodes.count, 2_000)
        XCTAssertEqual(layout.edges.count, 1_999)
        XCTAssertEqual(layout.nodes[1_999].frame.midY, layout.nodes[0].frame.midY, accuracy: accuracy)
    }
}
