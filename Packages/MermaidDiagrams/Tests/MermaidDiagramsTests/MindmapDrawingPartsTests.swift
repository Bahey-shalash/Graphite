import XCTest
@testable import MermaidDiagrams

final class MindmapDrawingPartsTests: XCTestCase {
    private func parts(_ source: String, title: String? = nil) throws -> (MindmapDrawingParts, MindmapLayout) {
        var diagram = try MindmapReading.mindmap(source)
        diagram.title = title
        let layout = MindmapLayoutEngine.layout(diagram, measurer: UniformWidthTextMeasurer(), font: DiagramFont(postScriptName: nil, size: 16))
        return (MindmapDrawingParts(layout: layout), layout)
    }

    func testLinksAndOutlinesAreGroupedByBranch() throws {
        let (parts, layout) = try parts("mindmap\n root\n  a\n   a1\n  b\n  c[box]")
        XCTAssertEqual(parts.branches.map(\.branchIndex), [0, 1, 2])
        XCTAssertFalse(parts.branches[0].nodeOutlines.isEmpty, "A node with children is a pill")
        XCTAssertTrue(parts.branches[1].nodeOutlines.isEmpty, "A leaf without delimiters is text alone")
        XCTAssertFalse(parts.branches[1].links.isEmpty)
        XCTAssertEqual(parts.branches[2].nodeOutlines.boundingBox, layout.nodes[4].frame)
        XCTAssertEqual(parts.branches[0].links.boundingBox.minX, layout.nodes[0].frame.maxX, accuracy: 0.01)
    }

    func testTheRootIsAPartOfItsOwn() throws {
        let (parts, layout) = try parts("mindmap\n root\n  child")
        XCTAssertEqual(parts.rootOutline.boundingBox, layout.nodes[0].frame)
        XCTAssertEqual(parts.nodeTexts.count, 2)
        XCTAssertNil(parts.title)
        XCTAssertNotNil(try self.parts("mindmap\n root", title: "Plan").0.title)
    }

    func testBranchesPastElevenShareTheFirstNumbersParts() throws {
        let source = "mindmap\nroot\n" + (1...12).map { number in "  [child \(number)]" }.joined(separator: "\n")
        let (parts, _) = try parts(source)
        XCTAssertEqual(parts.branches.map(\.branchIndex), Array(0..<11))
    }
}
