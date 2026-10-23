import XCTest
import GraphiteCore
import GraphiteIndex
import MermaidDiagrams
@testable import GraphiteUI
import GraphiteTestSupport

/// A ```mermaid block holding a Git graph: read and laid out with the note's other blocks, off the main actor, in the
/// note's text size; one that cannot be read keeps its source and says why; one that sets Git graph options stays code.
final class ReadingGitGraphTests: XCTestCase {
    private let typography = DiagramTypography(font: DiagramFont(postScriptName: nil, size: 17))
    private struct NotDrawnAsAGitGraph: Error {}

    private func gitGraph(_ source: String) throws -> ReadingGitGraph {
        guard case .gitGraph(let gitGraph) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else { throw NotDrawnAsAGitGraph() }
        return gitGraph
    }

    func testAGitGraphIsLaidOutInTheNotesTextSize() throws {
        let gitGraph = try gitGraph("gitGraph\n commit id:\"init\"\n branch develop\n commit tag:\"v1\"\n checkout main\n merge develop")
        XCTAssertEqual(gitGraph.layout.font.size, 17)
        XCTAssertEqual(gitGraph.layout.lanes.count, 2)
        XCTAssertEqual(gitGraph.layout.commits.count, 3)
        XCTAssertEqual(gitGraph.branchTexts, ["main: init", "develop: v1"])
    }

    func testAccessibilityTextComesFromTheDiagram() throws {
        let titled = try gitGraph("gitGraph\n title History\n accDescr: Two branches\n commit")
        XCTAssertEqual(titled.title, "History")
        XCTAssertEqual(titled.description, "Two branches")
        XCTAssertEqual(try gitGraph("gitGraph\n accTitle: Named\n title Shown\n commit").title, "Named")
        XCTAssertNil(try gitGraph("gitGraph\n commit").title)
        XCTAssertEqual(try gitGraph("gitGraph\n commit").branchTexts, ["main"])
    }

    func testAGitGraphThatCannotBeReadKeepsItsSourceAndWhy() throws {
        let source = "gitGraph\n commit\n checkout nope"
        guard case .unreadable(let shownSource, let failure) = try XCTUnwrap(ReadingDiagram(source: source, typography: typography)) else {
            return XCTFail("Shown as unreadable")
        }
        XCTAssertEqual(shownSource, source)
        XCTAssertEqual(failure, .reading(.invalidSyntax(line: 3, problem: .gitGraph(.unknownBranch(name: "nope")))))
    }

    func testAGitGraphThatSetsItsOptionsStaysCode() {
        XCTAssertNil(ReadingDiagram(source: "---\nconfig:\n  gitGraph:\n    showBranches: false\n---\ngitGraph\n commit", typography: typography))
        XCTAssertNil(ReadingDiagram(source: "%%{init: {'gitGraph': {'mainBranchName': 'trunk'}}}%%\ngitGraph\n commit\n checkout trunk",
                                    typography: typography))
    }

    func testEveryGitGraphProblemIsExplainedApart() {
        let problems: [GitGraphSyntaxProblem] = [
            .expectedBranchName, .expectedCommitType, .expectedOrder, .branchAlreadyExists(name: "b"), .unknownBranch(name: "b"),
            .branchMergedIntoItself(name: "b"), .currentBranchWithoutCommits(name: "b"), .mergedBranchWithoutCommits(name: "b"),
            .branchesShareTheirLastCommit(name: "b"), .duplicateCommitIdentifier("a"), .cherryPickWithoutIdentifier, .unknownCommit(identifier: "a"),
            .cherryPickFromCurrentBranch(identifier: "a"), .mergeCherryPickedWithoutParent(identifier: "a"), .notAParent(parent: "p", identifier: "a"),
        ]
        XCTAssertEqual(Set(problems.map(\.explanation)).count, problems.count)
        XCTAssertFalse(Set(problems.map(\.explanation)).contains(MermaidSyntaxProblem.unexpectedText("b").explanation))
    }

    func testTheReadingViewBuildsAGitGraphBlockBetweenTheTextAroundIt() async throws {
        let vault = try TemporaryVault.make(prefix: "GitGraphVault", for: self).root
        defer { try? FileManager.default.removeItem(at: vault) } // Best-effort removal of a temporary folder.
        let index = try VaultIndex(databaseURL: vault.appendingPathComponent(".index.sqlite"))
        let blocks = try await ReadingViewBuilder().build(source: "Before\n\n```mermaid\ngitGraph TB:\n  commit\n  branch b\n  commit\n```\n\nAfter",
                                                           note: try VaultPath("Note.md"), root: vault, index: index,
                                                           configuration: ReadingConfiguration()).blocks
        XCTAssertEqual(blocks.count, 3)
        guard case .diagram(_, .gitGraph(let gitGraph)) = blocks[1] else { return XCTFail("The Git graph is drawn") }
        XCTAssertEqual(gitGraph.layout.direction, .topToBottom)
    }
}
