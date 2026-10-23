import XCTest
@testable import MermaidDiagrams

/// A laid-out Git graph's geometry grouped by how it is painted: by series color, lines by kind, symbols and marks.
final class GitGraphDrawingPartsTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 16))

    private func parts(_ source: String) throws -> (layout: GitGraphLayout, parts: GitGraphDrawingParts) {
        let layout = try GitGraphLayoutEngine.layout(GitGraphReading.gitGraph(source), typography: typography)
        return (layout, GitGraphDrawingParts(layout: layout))
    }

    func testEachLaneHasAColorGroupWithItsLineAndNameBox() throws {
        let (layout, parts) = try parts("gitGraph\n commit\n branch develop\n commit\n branch hotfix\n commit")
        XCTAssertEqual(parts.colorGroups.map(\.seriesIndex), [0, 1, 2])
        XCTAssertEqual(parts.colorGroups[1].nameBoxes.boundingBox, layout.lanes[1].nameFrame)
        XCTAssertEqual(parts.names.map(\.lines), [["main"], ["develop"], ["hotfix"]])
    }

    func testLanesPastTheEighthTakeTheColorsAgain() throws {
        let source = "gitGraph\n commit\n" + (1...8).map { index in " branch b\(index)\n commit\n" }.joined()
        let (layout, parts) = try parts(source)
        XCTAssertEqual(layout.lanes.count, 9)
        XCTAssertEqual(parts.colorGroups.count, 8)
        XCTAssertTrue(parts.colorGroups[0].nameBoxes.boundingBox.contains(try XCTUnwrap(layout.lanes[8].nameFrame)))
    }

    func testLinesAreGroupedByKindAndAMergesLineByTheMergedLane() throws {
        let (layout, parts) = try parts("gitGraph\n commit id:\"s\"\n branch b\n commit\n commit id:\"x\"\n checkout main\n commit\n"
                                        + " cherry-pick id:\"x\"\n merge b")
        let main = parts.colorGroups[0]
        let laneB = parts.colorGroups[1]
        XCTAssertFalse(main.straightLines.isEmpty)
        XCTAssertFalse(main.cherryPickCurves.isEmpty, "The cherry-pick's line takes its own lane's color")
        XCTAssertTrue(laneB.cherryPickCurves.isEmpty)
        XCTAssertFalse(laneB.curves.isEmpty, "The branch's first commit and the merge from it")
        let merge = try XCTUnwrap(layout.commits.last)
        XCTAssertTrue(laneB.curves.boundingBox.insetBy(dx: -1, dy: -1).contains(merge.center))
    }

    func testEachSymbolHasItsShapeAndMarks() throws {
        let (layout, parts) = try parts("gitGraph\n commit type:HIGHLIGHT\n branch b\n commit type:REVERSE id:\"x\"\n checkout main\n merge b\n"
                                        + " cherry-pick id:\"x\"")
        let main = parts.colorGroups[0]
        let square = layout.commits[0].center
        XCTAssertTrue(main.symbols.boundingBox.contains(CGRect(x: square.x - 8, y: square.y - 8, width: 16, height: 16)))
        let ring = layout.commits[2].center
        XCTAssertEqual(main.rings.boundingBox, CGRect(x: ring.x - 6, y: ring.y - 6, width: 12, height: 12))
        let cross = parts.reverseCrosses.boundingBox
        XCTAssertEqual(cross.midX, layout.commits[1].center.x, accuracy: 0.001)
        XCTAssertEqual(cross.midY, layout.commits[1].center.y, accuracy: 0.001)
        XCTAssertEqual(cross.width, 6, accuracy: 0.001)
        XCTAssertEqual(cross.height, 6, accuracy: 0.001)
        XCTAssertFalse(parts.cherryStems.isEmpty)
        XCTAssertFalse(parts.cherryFruits.isEmpty)
    }

    func testIdsPatchesAndTagsKeepTheirPlaces() throws {
        let (layout, parts) = try parts("gitGraph\n commit id:\"init\" tag:\"v1\" tag:\"stable\"")
        let commit = try XCTUnwrap(layout.commits.first)
        let label = try XCTUnwrap(commit.label)
        XCTAssertEqual(parts.labels, [label])
        XCTAssertEqual(parts.labelPatches.boundingBox.midX, label.text.center.x, accuracy: 0.001)
        XCTAssertEqual(parts.labelPatches.boundingBox.midY, label.text.center.y, accuracy: 0.001)
        XCTAssertGreaterThan(parts.labelPatches.boundingBox.height, label.patchSize.height, "The patch is turned with its id")
        XCTAssertEqual(parts.tagBoxes.boundingBox, commit.tags[0].frame.union(commit.tags[1].frame))
        XCTAssertEqual(parts.tagTexts.map(\.lines), [["v1"], ["stable"]])
        XCTAssertFalse(parts.tagHoles.isEmpty)
    }
}
