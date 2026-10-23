import XCTest
@testable import MermaidDiagrams

/// A Git graph's statements played as Mermaid's Git graph database plays them: the cases of Mermaid 12.1.0's
/// `gitGraph.spec.ts` as Pele ports them in `tests/compat/git`, and the errors its renderer's tests list.
final class GitGraphDiagramBuilderTests: XCTestCase {
    private func gitGraph(_ source: String) throws -> GitGraphDiagram {
        try GitGraphReading.gitGraph(source)
    }

    private func readError(_ source: String) -> MermaidDiagramReadError? {
        GitGraphReading.readError(source)
    }

    func testCommitsGoOnTheCheckedOutBranchAfterItsLastCommit() throws {
        let diagram = try gitGraph("gitGraph:\n commit\n branch testBranch\n checkout testBranch\n commit\n")
        XCTAssertEqual(diagram.branches.map(\.name), ["main", "testBranch"])
        XCTAssertEqual(diagram.commits.map(\.branchIndex), [0, 1])
        XCTAssertEqual(diagram.commits.map(\.parentIndices), [[], [0]])
        let switched = try gitGraph("gitGraph:\n branch new\n switch new\n commit\n commit\n")
        XCTAssertEqual(switched.commits.map(\.branchIndex), [1, 1])
        XCTAssertEqual(switched.commits.map(\.parentIndices), [[], [0]])
    }

    func testABranchIsCheckedOutAsItIsMadeAndAnEmptyOneHasNoCommit() throws {
        XCTAssertEqual(try gitGraph("gitGraph\n commit\n branch b1\n commit\n").commits.map(\.branchIndex), [0, 1])
        let empty = try gitGraph("gitGraph:\nbranch new\ncheckout new\n")
        XCTAssertEqual(empty.commits, [])
        XCTAssertEqual(empty.branches.map(\.name), ["main", "new"])
        XCTAssertEqual(try gitGraph("gitGraph:\ncommit\nbranch b1\ncheckout b1\ncommit\ncommit\nbranch b2\n").branches.map(\.name), ["main", "b1", "b2"])
    }

    func testAMergeFollowsTheCurrentBranchThenTheMergedOne() throws {
        let diagram = try gitGraph("gitGraph:\ncommit\nbranch newbranch\ncheckout newbranch\ncommit\ncommit\ncheckout main\ncommit\nmerge newbranch\n")
        XCTAssertEqual(diagram.commits.count, 5)
        let merge = try XCTUnwrap(diagram.commits.last)
        XCTAssertEqual(merge.kind, .merge)
        XCTAssertEqual(merge.branchIndex, 0)
        XCTAssertEqual(merge.parentIndices, [3, 2])
        XCTAssertFalse(merge.hasWrittenIdentifier)
    }

    func testMergingTheBranchAnotherStartedFromIsAMergeToo() throws {
        let diagram = try gitGraph("gitGraph:\ncommit\nbranch newbranch\ncheckout newbranch\ncommit\ncommit\nmerge main\n")
        XCTAssertEqual(diagram.commits.count, 4)
        XCTAssertEqual(diagram.commits.last?.branchIndex, 1)
        XCTAssertEqual(diagram.commits.last?.parentIndices, [2, 0])
    }

    func testAMergeKeepsItsIdTagsAndType() throws {
        let diagram = try gitGraph("""
            gitGraph:
              commit
              branch testBranch
              checkout testBranch
              commit
              checkout main
              %% Merge Tag and ID
              merge testBranch tag: "merge-tag" id: "2-222"
              branch testBranch2
              checkout testBranch2
              commit
              checkout main
              %% Merge ID and Tag (reverse order)
              merge testBranch2 id: "4-444" tag: "merge-tag2" type:HIGHLIGHT
              branch testBranch3
              checkout testBranch3
              commit
              checkout main
              %% just Merge ID
              merge testBranch3 id: "6-666"
            """)
        XCTAssertEqual(diagram.commits.count, 7)
        XCTAssertEqual(diagram.commits.map(\.parentIndices), [[], [0], [0, 1], [2], [2, 3], [4], [4, 5]])
        XCTAssertEqual([2, 4, 6].map { index in diagram.commits[index].identifier }, ["2-222", "4-444", "6-666"])
        XCTAssertEqual([2, 4, 6].map { index in diagram.commits[index].hasWrittenIdentifier }, [true, true, true])
        XCTAssertEqual(diagram.commits[2].tags, [DiagramLabel("merge-tag")])
        XCTAssertEqual(diagram.commits[4].type, .highlight)
        XCTAssertNil(diagram.commits[6].type)
        XCTAssertEqual(diagram.branches.map(\.name), ["main", "testBranch", "testBranch2", "testBranch3"])
    }

    func testACherryPickFollowsItsBranchAndTheCommitItCopiesTaggedWithIt() throws {
        let diagram = try gitGraph("gitGraph\n commit id: \"ZERO\"\n branch develop\n commit id:\"A\"\n checkout main\n cherry-pick id:\"A\"\n")
        let pick = try XCTUnwrap(diagram.commits.last)
        XCTAssertEqual(pick.kind, .cherryPick)
        XCTAssertEqual(pick.branchIndex, 0)
        XCTAssertEqual(pick.parentIndices, [0, 1])
        XCTAssertEqual(pick.tags, [DiagramLabel("cherry-pick:A")])
        XCTAssertFalse(pick.hasWrittenIdentifier)
        let tagged = try gitGraph("gitGraph\n commit id: \"ZERO\"\n branch develop\n commit id:\"A\"\n checkout main\n cherry-pick id:\"A\" tag:\"MyTag\"\n")
        XCTAssertEqual(tagged.commits.last?.tags, [DiagramLabel("MyTag")])
        let untagged = try gitGraph("gitGraph\n commit id: \"ZERO\"\n branch develop\n commit id:\"A\"\n checkout main\n cherry-pick id:\"A\" tag:\"\"\n")
        XCTAssertEqual(untagged.commits.last?.tags, [])
    }

    func testACherryPickedMergeNamesTheParentItFollows() throws {
        let start = "gitGraph\n commit id: \"ZERO\"\n branch feature\n branch release\n checkout feature\n commit id: \"A\"\n commit id: \"B\"\n"
            + " checkout main\n merge feature id: \"M\"\n checkout release\n"
        XCTAssertEqual(try gitGraph(start + " cherry-pick id: \"M\" parent:\"B\"\n").commits.last?.tags, [DiagramLabel("cherry-pick:M|parent:B")])
        XCTAssertEqual(try gitGraph(start + " cherry-pick id: \"M\" parent:\"ZERO\" tag: \"v1.0\"\n").commits.last?.tags, [DiagramLabel("v1.0")])
        let more = try gitGraph(start + " commit id: \"C\"\n cherry-pick id: \"M\" tag: \"v2.1:ZERO\" parent:\"ZERO\"\n commit id: \"D\"\n")
        XCTAssertEqual(more.commits[5].tags, [DiagramLabel("v2.1:ZERO")])
        XCTAssertEqual(more.commits[5].branchIndex, 2)
        let empty = try gitGraph(start + " commit id: \"C\"\n cherry-pick id:\"M\" parent: \"ZERO\" tag:\"\"\n commit id: \"D\"\n"
                                 + " cherry-pick id:\"M\" tag:\"\" parent: \"B\"\n")
        XCTAssertEqual([empty.commits[5].tags, empty.commits[7].tags], [[], []])
    }

    func testMadeUpIdsArePelesTheSameEveryTimeAndSkipTakenOnes() throws {
        let source = "gitGraph\n commit\n commit\n branch b\n commit\n checkout main\n commit\n merge b"
        let identifiers = try gitGraph(source).commits.map(\.identifier)
        XCTAssertEqual(identifiers, ["0-9e3779b", "1-3c6ef36", "2-daa66d1", "3-78dde6c", "4-1715607"])
        XCTAssertEqual(try gitGraph(source).commits.map(\.identifier), identifiers)
        XCTAssertEqual(try gitGraph("gitGraph\n commit id:\"1-3c6ef36\"\n commit").commits.map(\.identifier), ["1-3c6ef36", "1-3c55bfc"])
    }

    func testStatementsTheHistoryCannotTakeAreRefusedWithTheirLine() {
        let cases: [(String, GitGraphSyntaxProblem, Int)] = [
            ("gitGraph\n commit\n branch main", .branchAlreadyExists(name: "main"), 3),
            ("gitGraph\n commit\n checkout nope", .unknownBranch(name: "nope"), 3),
            ("gitGraph\n commit\n branch b\n merge b", .branchMergedIntoItself(name: "b"), 4),
            ("gitGraph\n commit\n branch b\n merge main", .branchMergedIntoItself(name: "main"), 4),
            ("gitGraph\n merge b", .currentBranchWithoutCommits(name: "main"), 2),
            ("gitGraph\n commit\n merge b", .unknownBranch(name: "b"), 3),
            ("gitGraph\n branch b\n checkout main\n commit\n merge b", .mergedBranchWithoutCommits(name: "b"), 5),
            ("gitGraph\n commit\n branch b\n checkout main\n merge b", .branchesShareTheirLastCommit(name: "b"), 5),
            ("gitGraph\n commit id:\"a\"\n branch b\n commit\n checkout main\n commit\n merge b id:\"a\"", .duplicateCommitIdentifier("a"), 7),
            ("gitGraph\n commit\n cherry-pick id:\"nope\"", .unknownCommit(identifier: "nope"), 3),
            ("gitGraph\n commit\n cherry-pick", .cherryPickWithoutIdentifier, 3),
            ("gitGraph\n commit id:\"a\"\n cherry-pick id:\"a\"", .cherryPickFromCurrentBranch(identifier: "a"), 3),
            ("gitGraph\n branch b\n commit id:\"a\"\n checkout main\n cherry-pick id:\"a\"", .currentBranchWithoutCommits(name: "main"), 5),
            ("gitGraph\n commit id:\"z\"\n branch b\n commit id:\"a\"\n checkout main\n commit\n cherry-pick id:\"a\" parent:\"q\"",
             .notAParent(parent: "q", identifier: "a"), 7),
            ("gitGraph\n commit\n branch b\n commit\n checkout main\n commit\n merge b id:\"m\"\n checkout b\n cherry-pick id:\"m\"",
             .mergeCherryPickedWithoutParent(identifier: "m"), 9),
        ]
        for (source, problem, line) in cases {
            XCTAssertEqual(readError(source), GitGraphReading.problem(problem, line: line), source)
        }
    }

    func testTheSpecsInvalidHistoriesStopAtTheirFirstWrongStatement() {
        let cases: [(String, GitGraphSyntaxProblem, Int)] = [
            ("gitGraph\n commit\n branch testBranch\n commit\n branch main\n commit\n checkout main\n merge testBranch\n",
             .branchAlreadyExists(name: "main"), 5),
            ("gitGraph\n commit\n branch testBranch\n commit\n branch testBranch\n commit\n", .branchAlreadyExists(name: "testBranch"), 5),
            ("gitGraph\n commit\n checkout testBranch\n commit\n branch testBranch\n", .unknownBranch(name: "testBranch"), 3),
            ("gitGraph\n merge testBranch\n commit\n checkout testBranch\n", .currentBranchWithoutCommits(name: "main"), 2),
            ("gitGraph\n commit\n merge testBranch\n commit\n checkout testBranch\n", .unknownBranch(name: "testBranch"), 3),
            ("gitGraph\n commit\n branch testBranch\n merge testBranch\n", .branchMergedIntoItself(name: "testBranch"), 4),
            ("gitGraph\n commit id: \"1-111\"\n branch testBranch\n commit id: \"2-222\"\n commit id: \"3-333\"\n checkout main\n"
             + " merge testBranch id: \"1-111\"\n",
             .duplicateCommitIdentifier("1-111"), 7),
            ("gitGraph\n commit\n branch testBranch\n checkout main\n merge testBranch\n", .branchesShareTheirLastCommit(name: "testBranch"), 5),
            ("gitGraph\n branch test1\n\n checkout main\n commit\n merge test1\n", .mergedBranchWithoutCommits(name: "test1"), 6),
        ]
        for (source, problem, line) in cases {
            XCTAssertEqual(readError(source), GitGraphReading.problem(problem, line: line), source)
        }
    }

    func testARepeatedCommitIdIsRefusedWhereMermaidWouldDropTheEarlierCommit() {
        XCTAssertEqual(readError("gitGraph\n commit id:\"a\"\n commit id:\"b\"\n commit id:\"a\""),
                       GitGraphReading.problem(.duplicateCommitIdentifier("a"), line: 4))
    }

    func testASyntaxErrorAnywhereComesBeforeAStatementTheHistoryCannotTake() {
        XCTAssertEqual(readError("gitGraph\n checkout nope\n commit oops"), .invalidSyntax(line: 3, problem: .unexpectedText("oops")))
    }

    func testAGraphThatSetsOptionsStopsPlayingWithoutAnErrorWhereItsHistoryBreaks() throws {
        let diagram = try gitGraph("---\nconfig:\n  gitGraph:\n    mainBranchName: trunk\n---\ngitGraph\n commit\n checkout trunk\n commit")
        XCTAssertTrue(diagram.setsGitGraphOptions)
        XCTAssertEqual(diagram.commits.count, 1)
        XCTAssertEqual(readError("---\nconfig:\n  gitGraph:\n    showBranches: false\n---\ngitGraph\n commit oops"),
                       .invalidSyntax(line: 7, problem: .unexpectedText("oops")))
    }
}
