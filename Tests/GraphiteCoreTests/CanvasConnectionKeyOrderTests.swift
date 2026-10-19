import XCTest
import CoreGraphics
@testable import GraphiteCore

/// A new connection is written with its keys in the order Obsidian writes them, and leaves
/// out an end that has the format's default: `fromEnd: none` and `toEnd: arrow`.
final class CanvasConnectionKeyOrderTests: XCTestCase {
    private let emptyCanvas = "{}"

    private func addedEdgeLine(_ edge: CanvasEdge, readsBackAsWritten: Bool = true) throws -> String {
        let file = try CanvasFile(data: Data(emptyCanvas.utf8))
        let result = try file.applying([.add(nodes: [], edges: [edge])]).file
        let text = String(decoding: result.data, as: UTF8.self)
        if readsBackAsWritten { XCTAssertEqual(try CanvasFile(data: result.data).edges, [edge], "The connection reads back as written.") }
        return text
    }

    func testAConnectionWithEveryOptionIsWrittenInObsidiansKeyOrder() throws {
        let edge = CanvasEdge(id: "e1", fromNode: "a", toNode: "b", fromSide: .right, toSide: .left, fromEnd: .arrow, toEnd: .none,
                              color: .preset(3), label: "proves")
        XCTAssertEqual(try addedEdgeLine(edge),
                       "{\n\t\"edges\":[\n\t\t{\"id\":\"e1\",\"fromNode\":\"a\",\"fromSide\":\"right\",\"fromEnd\":\"arrow\",\"toNode\":\"b\",\"toSide\":\"left\",\"toEnd\":\"none\",\"color\":\"3\",\"label\":\"proves\"}\n\t]\n}")
    }

    func testAConnectionWithDefaultEndsLeavesThemOut() throws {
        let edge = CanvasEdge(id: "e2", fromNode: "a", toNode: "b")
        XCTAssertEqual(try addedEdgeLine(edge), "{\n\t\"edges\":[\n\t\t{\"id\":\"e2\",\"fromNode\":\"a\",\"toNode\":\"b\"}\n\t]\n}")
    }

    func testOnlyTheEndsThatDifferFromTheDefaultAreWritten() throws {
        XCTAssertEqual(try addedEdgeLine(CanvasEdge(id: "e3", fromNode: "a", toNode: "b", fromEnd: .arrow, toEnd: .arrow)),
                       "{\n\t\"edges\":[\n\t\t{\"id\":\"e3\",\"fromNode\":\"a\",\"fromEnd\":\"arrow\",\"toNode\":\"b\"}\n\t]\n}")
        XCTAssertEqual(try addedEdgeLine(CanvasEdge(id: "e4", fromNode: "a", toNode: "b", fromEnd: .none, toEnd: .none)),
                       "{\n\t\"edges\":[\n\t\t{\"id\":\"e4\",\"fromNode\":\"a\",\"toNode\":\"b\",\"toEnd\":\"none\"}\n\t]\n}")
    }

    func testAnEmptyLabelIsLeftOut() throws {
        XCTAssertEqual(try addedEdgeLine(CanvasEdge(id: "e5", fromNode: "a", toNode: "b", fromSide: .top, toSide: .bottom, label: ""), readsBackAsWritten: false).contains("label"), false)
    }
}
