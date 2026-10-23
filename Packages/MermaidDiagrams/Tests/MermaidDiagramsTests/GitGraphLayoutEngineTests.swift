import XCTest
@testable import MermaidDiagrams

/// Git graphs laid out with Pele's measurements, text measured at fixed widths: the cases of Pele's
/// `tests/render/git.test.ts` that do not depend on options, and the spacing and routing they rest on.
final class GitGraphLayoutEngineTests: XCTestCase {
    private let smallText = UniformWidthTextMeasurer(characterWidth: 6, fontSize: 12, lineHeight: 18)
    private let branchText = UniformWidthTextMeasurer(characterWidth: 7, fontSize: 14, lineHeight: 21)
    private let titleText = UniformWidthTextMeasurer()

    /// Pele's example of every statement: three branches, ten commits of every symbol, tags, a cherry-pick and merges.
    private let flow = """
          commit id: "init"
          commit type: REVERSE tag: "v0.1"
          branch develop
          commit id: "feat" msg: "A message"
          commit type: HIGHLIGHT
          checkout main
          commit tag: "v0.2" tag: "stable"
          merge develop id: "merged" tag: "v1.0"
          branch hotfix
          commit id: "fix"
          checkout develop
          commit
          cherry-pick id: "fix"
          checkout main
          merge hotfix
        """

    private func laidOut(_ source: String) throws -> GitGraphLayout {
        try GitGraphLayoutEngine.layout(GitGraphReading.gitGraph(source), smallText: smallText, branchText: branchText, titleText: titleText,
                                        font: UniformWidthLayout.font)
    }

    func testALanePerBranchAndASymbolPerCommit() throws {
        let layout = try laidOut("gitGraph\n" + flow)
        XCTAssertEqual(layout.lanes.map { lane in lane.name?.lines }, [["main"], ["develop"], ["hotfix"]])
        XCTAssertEqual(layout.commits.map(\.laneIndex), [0, 0, 1, 1, 0, 0, 2, 1, 1, 0])
        XCTAssertEqual(layout.commits.map(\.symbol), [.normal, .reverse, .normal, .highlight, .normal, .merge, .normal, .normal, .cherryPick, .merge])
        XCTAssertEqual(try laidOut("gitGraph\n commit\n branch b\n commit\n checkout main\n commit\n merge b type: REVERSE").commits.last?.symbol, .reverse)
    }

    func testIdsLabelEveryCommitButUnnamedMergesAndCherryPicks() throws {
        let layout = try laidOut("gitGraph\n" + flow)
        let labels = layout.commits.compactMap(\.label)
        XCTAssertEqual(labels.count, 8)
        XCTAssertEqual(labels.map(\.text.lines.first), ["init", "1-3c6ef36", "feat", "3-78dde6c", "4-1715607", "merged", "fix", "7-f1bbcd8"])
        XCTAssertEqual(Set(labels.map(\.angle)), [-.pi / 4])
        XCTAssertEqual(labels[0].patchSize, CGSize(width: 4 * 6 + 4, height: 18 - 4))
    }

    func testTagsIncludeTheCherryPicksOwnAndNoEmptyOne() throws {
        let layout = try laidOut("gitGraph\n" + flow)
        XCTAssertEqual(layout.commits.flatMap(\.tags).map(\.text.lines), [["v0.1"], ["v0.2"], ["stable"], ["v1.0"], ["cherry-pick:fix"]])
        let untagged = try laidOut("gitGraph\n commit id:\"a\" tag:\"\"\n branch b\n commit id:\"c\"\n checkout main\n commit\n cherry-pick id:\"c\" tag:\"\"")
        XCTAssertEqual(untagged.commits.flatMap(\.tags), [])
    }

    func testTagsStackAboveTheirCommitTheFirstFurthestOut() throws {
        let layout = try laidOut("gitGraph\n commit tag:\"v0.2\" tag:\"stable\"")
        let commit = try XCTUnwrap(layout.commits.first)
        XCTAssertEqual(commit.tags.map(\.text.lines), [["v0.2"], ["stable"]])
        XCTAssertLessThan(commit.tags[0].frame.maxY, commit.tags[1].frame.minY)
        XCTAssertEqual(commit.tags[1].frame.maxY, commit.center.y - GitGraphGeometry.dotRadius - GitGraphGeometry.tagGap, accuracy: 0.001)
        XCTAssertEqual(commit.tags[1].frame.midX, commit.center.x, accuracy: 0.001)
        XCTAssertEqual(commit.tags[1].frame.width, 7 + 4 + 6 * 6 + 6)
    }

    func testConnectorsRunAlongALaneAcrossLanesOrDashedForACherryPick() throws {
        let layout = try laidOut("gitGraph\n" + flow)
        XCTAssertEqual(layout.connectors.count, 12)
        XCTAssertEqual(layout.connectors.filter { connector in connector.style == .alongLane }.count, 7)
        XCTAssertEqual(layout.connectors.filter { connector in connector.style == .acrossLanes }.count, 4)
        XCTAssertEqual(layout.connectors.filter { connector in connector.style == .cherryPick }.count, 1)
        let fromDevelop = layout.connectors[5]
        XCTAssertEqual(fromDevelop.style, .acrossLanes)
        XCTAssertEqual(fromDevelop.laneIndex, 1, "A merge's line takes the merged branch's color")
        XCTAssertTrue(fromDevelop.path.segments.contains { segment in if case .curve = segment { true } else { false } })
    }

    func testAMergeRunsAlongTheMergedLaneWhenItIsFreeAndTurnsInJustBeforeTheMerge() throws {
        let layout = try laidOut("gitGraph\n commit\n branch b\n commit\n checkout main\n commit\n merge b")
        let merge = try XCTUnwrap(layout.connectors.last)
        XCTAssertEqual(merge.path.start, layout.commits[1].center)
        guard case .line(let runEnd) = merge.path.segments.first, case .curve(let end, _, _) = merge.path.segments.last else {
            return XCTFail("A line along the merged lane, then a turn")
        }
        XCTAssertEqual(runEnd.y, layout.commits[1].center.y)
        XCTAssertEqual(runEnd.x, layout.commits[3].center.x - GitGraphGeometry.curveLength, accuracy: 0.001)
        XCTAssertEqual(end, layout.commits[3].center)
    }

    func testABranchsFirstCommitLeavesItsParentAtOnceWhenItsLaneIsFree() throws {
        let layout = try laidOut("gitGraph\n commit\n commit\n branch b\n commit")
        let first = try XCTUnwrap(layout.connectors.last)
        guard case .curve(let turnEnd, _, _) = first.path.segments.first, case .line(let end) = first.path.segments.last else {
            return XCTFail("A turn, then a line along the branch's lane")
        }
        XCTAssertEqual(turnEnd.x, layout.commits[1].center.x + GitGraphGeometry.curveLength, accuracy: 0.001)
        XCTAssertEqual(turnEnd.y, layout.commits[2].center.y)
        XCTAssertEqual(end, layout.commits[2].center)
    }

    func testACherryPickAcrossABusyLaneRunsInTheStripBesideIt() throws {
        let layout = try laidOut("gitGraph\n commit\n branch b\n commit id:\"x\"\n checkout main\n commit\n commit\n cherry-pick id:\"x\"")
        let pick = try XCTUnwrap(layout.connectors.last)
        XCTAssertEqual(pick.style, .cherryPick)
        XCTAssertEqual(pick.laneIndex, 0)
        guard pick.path.segments.count == 3, case .line(let runEnd) = pick.path.segments[1] else { return XCTFail("A turn, a run and a turn") }
        let mainLane = layout.commits[0].center.y
        let laneB = layout.commits[1].center.y
        XCTAssertGreaterThan(runEnd.y, mainLane)
        XCTAssertLessThan(runEnd.y, laneB)
    }

    func testCommitsAreAStepApartUnlessTheirTagsNeedMore() throws {
        let plain = try laidOut("gitGraph\n commit\n commit\n commit")
        XCTAssertEqual(plain.commits.map(\.center.x).adjacentDifferences, [44, 44])
        let tagged = try laidOut("gitGraph\n commit tag:\"release-candidate\"\n commit tag:\"release-candidate\"")
        let tagLength: CGFloat = 7 + 4 + 17 * 6 + 6
        XCTAssertEqual(tagged.commits[1].center.x - tagged.commits[0].center.x, tagLength + 8, accuracy: 0.001)
    }

    func testLanesAreALaneGapApartUnlessTheirIdsAndNamesNeedMore() throws {
        let layout = try laidOut("gitGraph\n commit id:\"a\"\n branch b\n commit id:\"b\"")
        let labelReach = 7 + 3 + CGFloat(0.5).squareRoot() * (6 + 18)
        let nameReach: CGFloat = 21 / 2 + 2
        XCTAssertEqual(layout.commits[1].center.y - layout.commits[0].center.y, max(44, labelReach + nameReach + 8), accuracy: 0.001)
        let close = try laidOut("gitGraph\n branch b")
        XCTAssertEqual(close.lanes[1].lineStart.y - close.lanes[0].lineStart.y, 44, accuracy: 0.001)
    }

    func testLanesRunAcrossTopToBottomAndUpsideDownBottomToTop() throws {
        let body = "\n commit\n commit\n branch b\n commit\n commit\n checkout main\n commit"
        let across = try laidOut("gitGraph" + body).commits.map(\.center)
        XCTAssertGreaterThan(across[1].x, across[0].x)
        XCTAssertEqual(across[1].y, across[0].y)
        XCTAssertGreaterThan(across[2].y, across[0].y)
        let downLayout = try laidOut("gitGraph TB:" + body)
        let down = downLayout.commits.map(\.center)
        XCTAssertGreaterThan(down[1].y, down[0].y)
        XCTAssertEqual(down[1].x, down[0].x)
        XCTAssertGreaterThan(down[2].x, down[0].x)
        XCTAssertGreaterThan(downLayout.size.height, downLayout.size.width)
        let upLayout = try laidOut("gitGraph BT:" + body)
        let up = upLayout.commits.map(\.center)
        XCTAssertLessThan(up[1].y, up[0].y)
        XCTAssertGreaterThan(up[2].x, up[0].x)
        XCTAssertEqual(upLayout.size.height, downLayout.size.height)
        XCTAssertEqual(upLayout.commits.first?.label?.angle, .pi / 4)
    }

    func testAnIdTrailsFromItsCornerBesideTheDot() throws {
        let layout = try laidOut("gitGraph\n commit id:\"abcd\"")
        let commit = try XCTUnwrap(layout.commits.first)
        let label = try XCTUnwrap(commit.label)
        XCTAssertLessThan(label.text.center.x, commit.center.x + GitGraphGeometry.labelOffset)
        XCTAssertGreaterThan(label.text.center.y, commit.center.y + GitGraphGeometry.dotRadius)
        let vertical = try XCTUnwrap(laidOut("gitGraph TB:\n commit id:\"abcd\"").commits.first)
        XCTAssertLessThan(try XCTUnwrap(vertical.label).text.center.x, vertical.center.x - GitGraphGeometry.dotRadius)
    }

    func testAGraphWithoutCommitsDrawsItsLanes() throws {
        let empty = try laidOut("gitGraph")
        XCTAssertEqual(empty.lanes.count, 1)
        XCTAssertEqual(empty.commits, [])
        XCTAssertGreaterThan(empty.size.width, 0)
        let branches = try laidOut("gitGraph\n branch a\n branch \"b c\"")
        XCTAssertEqual(branches.lanes.map { lane in lane.name?.lines }, [["main"], ["a"], ["b c"]])
    }

    func testTheTitleIsAboveTheGraphCenteredOnThePage() throws {
        let layout = try laidOut("gitGraph\n title A title wider than the graph is\n commit")
        let title = try XCTUnwrap(layout.title)
        XCTAssertEqual(title.center.x, layout.size.width / 2, accuracy: 0.5)
        XCTAssertEqual(title.frame.minY, GitGraphLayoutEngine.padding, accuracy: 0.001)
        XCTAssertGreaterThan(try XCTUnwrap(layout.commits.first).center.y, title.frame.maxY + GitGraphLayoutEngine.titleGap)
    }

    func testEverythingLiesOnThePage() throws {
        for header in ["gitGraph", "gitGraph TB:", "gitGraph BT:"] {
            let layout = try laidOut(header + "\n title History\n" + flow)
            let page = CGRect(origin: .zero, size: layout.size).insetBy(dx: -0.001, dy: -0.001)
            let frames = layout.commits.flatMap { commit in (commit.label.map { label in [Self.turnedFrame(label)] } ?? []) + commit.tags.map(\.frame) }
                + layout.lanes.compactMap(\.nameFrame) + [try XCTUnwrap(layout.title).frame]
            for frame in frames { XCTAssertTrue(page.contains(frame), "\(header): \(frame) in \(layout.size)") }
            for commit in layout.commits { XCTAssertTrue(page.contains(commit.center), header) }
        }
    }

    func testAGraphThatSetsOptionsIsNotLaidOut() throws {
        let diagram = try GitGraphReading.gitGraph("---\nconfig:\n  gitGraph:\n    showBranches: false\n---\ngitGraph\n commit")
        XCTAssertThrowsError(try GitGraphLayoutEngine.layout(diagram, smallText: smallText, branchText: branchText, titleText: titleText,
                                                             font: UniformWidthLayout.font)) { error in
            XCTAssertEqual(error as? GitGraphLayoutError, .optionsNotApplied)
        }
    }
}

extension GitGraphLayoutEngineTests {
    /// The rectangle a turned id covers.
    static func turnedFrame(_ label: GitGraphLayoutCommitLabel) -> CGRect {
        let size = label.text.size
        let halfWidth = abs(size.width / 2 * cos(label.angle)) + abs(size.height / 2 * sin(label.angle))
        let halfHeight = abs(size.width / 2 * sin(label.angle)) + abs(size.height / 2 * cos(label.angle))
        return CGRect(x: label.text.center.x - halfWidth, y: label.text.center.y - halfHeight, width: 2 * halfWidth, height: 2 * halfHeight)
    }
}

private extension Array where Element == CGFloat {
    var adjacentDifferences: [CGFloat] {
        zip(dropFirst(), self).map { next, previous in next - previous }
    }
}
