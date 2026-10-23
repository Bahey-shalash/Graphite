import XCTest
import SwiftUI
import MermaidDiagrams
@testable import GraphiteUI

final class ReadingGitGraphShapesTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))
    private struct NotDrawnAsAGitGraph: Error {}

    private func gitGraph(_ source: String) throws -> ReadingGitGraph {
        guard case .gitGraph(let gitGraph) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAGitGraph() }
        return gitGraph
    }

    func testLanesLinesAndSymbolsKeepTheirSeriesColorAndPaths() throws {
        let gitGraph = try gitGraph("gitGraph\n commit\n branch b\n commit\n checkout main\n commit\n merge b")
        XCTAssertEqual(gitGraph.shapes.colorGroups.map(\.seriesIndex), [0, 1])
        let main = gitGraph.shapes.colorGroups[0]
        XCTAssertEqual(main.nameBoxes.boundingRect, gitGraph.layout.lanes[0].nameFrame)
        XCTAssertFalse(main.straightLines.isEmpty)
        XCTAssertFalse(main.rings.isEmpty)
        XCTAssertFalse(gitGraph.shapes.colorGroups[1].curves.isEmpty, "The branch's first commit and the merge from it")
        XCTAssertTrue(gitGraph.shapes.reverseCrosses.isEmpty)
    }

    func testAnIdIsTurnedAboutItsCenterLineByLine() throws {
        let single = try gitGraph("gitGraph\n commit id:\"init\"")
        let line = try XCTUnwrap(single.shapes.labelLines.first)
        let label = try XCTUnwrap(single.layout.commits.first?.label)
        XCTAssertEqual(line.angle, -.pi / 4, accuracy: 1e-9)
        XCTAssertEqual(line.line.center.x, label.text.center.x, accuracy: 1e-9)
        XCTAssertEqual(line.line.center.y, label.text.center.y, accuracy: 1e-9)
        XCTAssertEqual(line.line.font.size, 12, "Ids are three quarters of the text size")
        let twoLines = try gitGraph("gitGraph\n commit id:\"first<br>second\"").shapes.labelLines
        XCTAssertEqual(twoLines.map(\.line.text), ["first", "second"])
        let step = CGVector(dx: twoLines[1].line.center.x - twoLines[0].line.center.x, dy: twoLines[1].line.center.y - twoLines[0].line.center.y)
        XCTAssertEqual(step.dx, step.dy, accuracy: 1e-9, "The next line is below the first across the turned text")
        XCTAssertGreaterThan(step.dx, 0)
    }

    func testNamesAreOnTheirBoxesAndTagsComeBeforeTheTitle() throws {
        let gitGraph = try gitGraph("gitGraph\n title History\n commit tag:\"v1\"\n branch b")
        XCTAssertEqual(gitGraph.shapes.nameLines.map(\.text), ["main", "b"])
        XCTAssertEqual(gitGraph.shapes.nameLines.first?.font.size, 14, "Names are seven eighths of the text size")
        XCTAssertEqual(gitGraph.shapes.textLines.map(\.text), ["v1", "History"])
        XCTAssertEqual(gitGraph.shapes.textLines.map(\.isBold), [false, true])
        XCTAssertFalse(gitGraph.shapes.tagBoxes.isEmpty)
        XCTAssertFalse(gitGraph.shapes.labelPatches.isEmpty)
    }
}
