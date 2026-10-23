import XCTest
@testable import MermaidDiagrams

/// The inputs of Mermaid 12.1.0's parser test `gitGraph.test.ts` and the parsing cases of its `gitGraph.spec.ts`, as
/// Pele ports them in `tests/compat/git`, with the documentation's forms, read through `MermaidDiagramReader`.
final class GitGraphParserTests: XCTestCase {
    private func gitGraph(_ source: String) throws -> GitGraphDiagram {
        try GitGraphReading.gitGraph(source)
    }

    private func readError(_ source: String) -> MermaidDiagramReadError? {
        GitGraphReading.readError(source)
    }

    private func commit(_ source: String) throws -> GitGraphCommit {
        try XCTUnwrap(gitGraph(source).commits.first)
    }

    func testTheKeywordTakesAColonOrADirectionAndItsColon() throws {
        XCTAssertEqual(try gitGraph("gitGraph:\n commit\n").commits.count, 1)
        XCTAssertEqual(try gitGraph("gitGraph:\n commit\n").direction, .leftToRight)
        XCTAssertEqual(try gitGraph("gitGraph TB:\ncommit\n").direction, .topToBottom)
        XCTAssertEqual(try gitGraph("gitGraph BT:\ncommit\n").direction, .bottomToTop)
        XCTAssertEqual(try gitGraph("gitGraph LR:\n commit").direction, .leftToRight)
        XCTAssertEqual(try gitGraph("gitGraph BT :\ncommit id:\"a\" msg:\"m\" tag:\"t\" tag:\"u\" type:REVERSE").direction, .bottomToTop)
        XCTAssertEqual(try gitGraph("gitGraph :\n commit").commits.count, 1)
        XCTAssertEqual(try gitGraph("gitGraph").commits, [])
        XCTAssertEqual(try gitGraph("gitGraph").branches.map(\.name), ["main"])
    }

    func testADirectionWithoutItsColonOrAfterTheJoinedColonIsNoStatement() {
        XCTAssertEqual(readError("gitGraph TB\n commit"), .invalidSyntax(line: 1, problem: .unexpectedText("TB")))
        XCTAssertEqual(readError("gitGraph:TB:\n commit"), .invalidSyntax(line: 1, problem: .unexpectedText("TB:")))
        XCTAssertEqual(readError("gitGraph LR::\n commit"), .invalidSyntax(line: 1, problem: .unexpectedText(":")))
    }

    func testAStatementMayFollowTheKeywordOnItsLine() throws {
        let onTheKeywordsLine = try commit("gitGraph commit \"msg\" id: \"x\"")
        XCTAssertEqual(onTheKeywordsLine.identifier, "x")
        XCTAssertEqual(onTheKeywordsLine.message, "msg")
        XCTAssertEqual(try gitGraph("gitGraph: commit\nbranch \"quoted name\" order: 3\ncheckout \"quoted name\"\ncommit").branches.map(\.name),
                       ["main", "quoted name"])
    }

    func testACommitTakesItsIdMessageTagsAndTypeInAnyOrder() throws {
        let full = try commit("gitGraph\n  commit id:\"1\" msg:\"Fix bug\" tag:\"v1.2\" type:NORMAL\n")
        XCTAssertEqual(full.identifier, "1")
        XCTAssertTrue(full.hasWrittenIdentifier)
        XCTAssertEqual(full.message, "Fix bug")
        XCTAssertEqual(full.tags, [DiagramLabel("v1.2")])
        XCTAssertEqual(full.type, .normal)
        for source in ["commit type: HIGHLIGHT tag: \"t\" msg: \"m\" id: \"a\"", "commit tag:\"t\" msg:\"m\" id:\"a\" type:HIGHLIGHT",
                       "commit msg: \"m\" id: \"a\" type: HIGHLIGHT tag: \"t\""] {
            let reordered = try commit("gitGraph:\n " + source)
            XCTAssertEqual([reordered.identifier, reordered.message], ["a", "m"], source)
            XCTAssertEqual(reordered.tags, [DiagramLabel("t")], source)
            XCTAssertEqual(reordered.type, .highlight, source)
        }
        XCTAssertEqual(try commit("gitGraph\n  commit type:REVERSE\n").type, .reverse)
    }

    func testAMessageMayBeWrittenWithoutItsKeyAndKeepsItsCharacters() throws {
        XCTAssertEqual(try commit("gitGraph:\ncommit \"a commit\"\n").message, "a commit")
        XCTAssertEqual(try commit("gitGraph\n  commit msg:\"Fix issue #123: Handle errors\"\n").message, "Fix issue #123: Handle errors")
        let onlyMessage = try commit("gitGraph\n  commit msg:\"Initial release\"\n")
        XCTAssertEqual(onlyMessage.message, "Initial release")
        XCTAssertFalse(onlyMessage.hasWrittenIdentifier)
        XCTAssertNil(onlyMessage.type)
    }

    func testACommitWithoutValuesHasAMadeUpIdNoTagsAndNoType() throws {
        let bare = try commit("gitGraph:\n        commit\n        ")
        XCTAssertEqual(bare.identifier, "0-9e3779b")
        XCTAssertFalse(bare.hasWrittenIdentifier)
        XCTAssertEqual(bare.message, "")
        XCTAssertEqual(bare.tags, [])
        XCTAssertNil(bare.type)
        XCTAssertEqual(bare.kind, .commit)
    }

    func testBranchNamesHoldDigitsDotsSlashesHyphensAndUnderscores() throws {
        let source = "gitGraph\n commit\n branch 1.0.1\n branch feature/test-branch\n branch my-feature_branch\n branch azAZ_-./test\n"
        XCTAssertEqual(try gitGraph(source).branches.map(\.name), ["main", "1.0.1", "feature/test-branch", "my-feature_branch", "azAZ_-./test"])
    }

    func testANameThatStartsWithAKeywordIsAName() throws {
        let source = """
            gitGraph:
              commit
              %% branch names starting with numbers are not recommended, but are supported by git
              branch branch01
              branch checkout02
              branch cherry-pick03
              branch branch/example-branch
              branch merge/test_merge
              %% single character branch name
              branch A
            """
        XCTAssertEqual(try gitGraph(source).branches.map(\.name),
                       ["main", "branch01", "checkout02", "cherry-pick03", "branch/example-branch", "merge/test_merge", "A"])
    }

    func testQuotedBranchNamesAndNamesLikeJavaScriptsOwnAreOrdinaryNames() throws {
        let quoted = try gitGraph("gitGraph:\n commit\n branch \"branch\"\n checkout \"branch\"\n commit\n checkout main\n merge \"branch\"\n")
        XCTAssertEqual(quoted.branches.map(\.name), ["main", "branch"])
        XCTAssertEqual(quoted.commits.map(\.branchIndex), [0, 1, 0])
        for name in ["__proto__", "constructor"] {
            let diagram = try gitGraph("gitGraph\n commit id:\"\(name)\"\n branch \(name)\n checkout \(name)\n commit\n checkout main\n merge \(name)\n")
            XCTAssertEqual(diagram.commits.count, 3)
            XCTAssertEqual(diagram.commits.first?.identifier, name)
            XCTAssertEqual(diagram.branches.map(\.name), ["main", name])
        }
    }

    func testBranchesAreOrderedByTheirOrderThenAsTheyWereCreated() throws {
        let ordered = "gitGraph:\n commit\n branch test1 order: 3\n branch test2 order: 2\n branch test3 order: 1\n"
        XCTAssertEqual(try gitGraph(ordered).branches.map(\.name), ["main", "test3", "test2", "test1"])
        let mixed = "gitGraph:\n commit\n branch test1 order: 1\n branch test2\n branch test3\n"
        XCTAssertEqual(try gitGraph(mixed).branches.map(\.name), ["main", "test2", "test3", "test1"])
        XCTAssertEqual(try gitGraph("gitGraph\n commit\n  branch feature order:1\n").branches.map(\.name), ["main", "feature"])
    }

    func testABranchNameIsDrawnWithOnlyBreaksAsMarkup() throws {
        let branch = try XCTUnwrap(gitGraph("gitGraph\n commit\n branch \"one<br>two <i>t</i>\"").branches.last)
        XCTAssertEqual(branch.label.lines, ["one", "two <i>t</i>"])
    }

    func testAccessibilityTitleAndDescription() throws {
        let diagram = try gitGraph("gitGraph:\n  accTitle: This is a title\n  accDescr: This is a description\ncommit\n")
        XCTAssertEqual(diagram.accessibilityTitle, "This is a title")
        XCTAssertEqual(diagram.accessibilityDescription, "This is a description")
        let multiline = try gitGraph("gitGraph\n  accDescr {\n    Detailed description\n    across multiple lines\n  }\n  commit\n")
        XCTAssertEqual(multiline.accessibilityDescription, "Detailed description across multiple lines")
        XCTAssertEqual(multiline.commits.count, 1)
    }

    func testTheTitleIsItsOwnElseTheFrontMattersAndKeepsOneSpaceBetweenWords() throws {
        XCTAssertEqual(try gitGraph("---\ntitle: From front matter\n---\ngitGraph\n commit").title, "From front matter")
        XCTAssertEqual(try gitGraph("---\ntitle: From front matter\n---\ngitGraph\n title Own\n commit").title, "Own")
        XCTAssertEqual(try gitGraph("gitGraph\n title   Two \t  words  %% a comment\n").title, "Two words")
        XCTAssertNil(try gitGraph("gitGraph\n title\n commit").title)
    }

    func testCommentsAndDirectivesAreSkipped() throws {
        XCTAssertEqual(try gitGraph("%%{init: {\"theme\":\"dark\"}}%%\ngitGraph %% c\ncommit %% d\n").commits.count, 1)
        XCTAssertEqual(try gitGraph("gitGraph\n %% a comment\n commit\n %%{init: {}}%%\n commit").commits.count, 2)
    }

    func testTheMermaidSpecsIntegrationExampleReadsEveryStatement() throws {
        let diagram = try gitGraph("""

                gitGraph TB:
                accTitle: Complex Example
                commit id:"init" type:NORMAL
                branch feature
                commit id:"feat1" msg:"Add feature"
                checkout main
                merge feature tag:"v1.0"
                cherry-pick id:"feat1" tag:"critical fix"

            """)
        XCTAssertEqual(diagram.direction, .topToBottom)
        XCTAssertEqual(diagram.accessibilityTitle, "Complex Example")
        XCTAssertEqual(diagram.commits.map(\.kind), [.commit, .commit, .merge, .cherryPick])
        XCTAssertEqual(diagram.commits.map(\.message), ["", "Add feature", "", ""])
        XCTAssertEqual(diagram.commits[2].tags, [DiagramLabel("v1.0")])
    }

    func testValuesAStatementDoesNotTakeAreRefused() {
        XCTAssertEqual(readError("gitGraph\n  commit unknown:\"oops\"\n"), .invalidSyntax(line: 2, problem: .unexpectedText("unknown:\"oops\"")))
        XCTAssertEqual(readError("gitGraph\n  commit id:\"2\" msg:\"Malformed commit\" oops:\"ignored\"\n"),
                       .invalidSyntax(line: 2, problem: .unexpectedText("oops:\"ignored\"")))
        XCTAssertEqual(readError("gitGraph\n  merge feature random:\"ignored\"\n"), .invalidSyntax(line: 2, problem: .unexpectedText("random:\"ignored\"")))
        XCTAssertEqual(readError("gitGraph\n  merge feature msg:\"no\"\n"), .invalidSyntax(line: 2, problem: .unexpectedText("msg:\"no\"")))
        XCTAssertEqual(readError("gitGraph\n commit id:\"123\" commit id:\"321\" cherry-pick id:\"123\"\n"),
                       .invalidSyntax(line: 2, problem: .unexpectedText("commit id:\"321\" cherry-p")))
    }

    func testEachValueHasItsForm() {
        XCTAssertEqual(readError("gitGraph\n  branch feature order:xyz\n"), GitGraphReading.problem(.expectedOrder, line: 2))
        XCTAssertEqual(readError("gitGraph\n  commit type:FOO\n"), GitGraphReading.problem(.expectedCommitType, line: 2))
        XCTAssertEqual(readError("gitGraph\n  commit type:\"NORMAL\"\n"), GitGraphReading.problem(.expectedCommitType, line: 2))
        XCTAssertEqual(readError("gitGraph\n  commit id: abc\n"), .invalidSyntax(line: 2, problem: .expectedQuotedText))
        XCTAssertEqual(readError("gitGraph\n  branch\n"), GitGraphReading.problem(.expectedBranchName, line: 2))
        XCTAssertEqual(readError("gitGraph\n  checkout commit\n"), GitGraphReading.problem(.expectedBranchName, line: 2))
        XCTAssertEqual(readError("gitGraph\n  commit id:\"a\n"), .invalidSyntax(line: 2, problem: .unclosedQuotation))
    }

    func testKeywordsAreWrittenInTheirCaseAndAStatementEndsItsLine() {
        XCTAssertEqual(readError("gitGraph\n  Commit\n"), .invalidSyntax(line: 2, problem: .unexpectedText("Commit")))
        XCTAssertEqual(readError("gitGraph\n  commit commit\n"), .invalidSyntax(line: 2, problem: .unexpectedText("commit")))
        XCTAssertEqual(readError("gitGraph\n  gitGraph\n"), .invalidSyntax(line: 2, problem: .unexpectedText("gitGraph")))
        XCTAssertEqual(readError("gitGraph\n  branch title1\n"), GitGraphReading.problem(.expectedBranchName, line: 2))
    }

    func testCommitsBranchesAndTagsCountAgainstTheNodeLimit() {
        var limits = MermaidDiagramLimits.standard
        limits.maximumNodeCount = 3
        XCTAssertEqual(GitGraphReading.readError("gitGraph\n commit\n commit\n commit", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertEqual(GitGraphReading.readError("gitGraph\n commit tag:\"a\" tag:\"b\"", limits: limits), .tooManyNodes(limit: 3))
        XCTAssertNil(GitGraphReading.readError("gitGraph\n commit tag:\"a\"", limits: limits))
    }
}
